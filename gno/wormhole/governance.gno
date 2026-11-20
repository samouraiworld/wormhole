package core

import (
	"chain"
	"chain/banker"
	"crypto/bech32"
	"strconv"
)

const (
	governanceChain = 1
	// governanceEmitter is 0x00…04 and coreModule is "Core" left-padded to
	// 32 bytes.
	governanceEmitter = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" +
		"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x04"
	coreModule = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" +
		"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00Core"
	actionGuardianSetUpgrade = 2
	actionSetMessageFee      = 3
	actionTransferFees       = 4
)

// SubmitGovernance verifies and executes a Core governance VAA: a
// guardian-set upgrade (action 2), SetMessageFee (3) or TransferFees (4).
// Actions 1 and 5 are refused. It does not read the chain ID at runtime, so
// governance acts on any network.
func SubmitGovernance(cur realm, raw []byte) {
	now := blockTime()
	v := verify(raw, governanceBound, now)
	if v.GuardianSetIndex != currentIndex {
		panic("core: governance-not-current-set")
	}
	if v.EmitterChain != governanceChain {
		panic("core: governance-wrong-chain")
	}
	if string(v.EmitterAddress[:]) != governanceEmitter {
		panic("core: governance-wrong-emitter")
	}
	if consumed.Has(string(v.Digest[:])) {
		panic("core: governance-replay")
	}
	p := v.Payload
	if len(p) < 33 {
		panic("core: governance-malformed")
	}
	if string(p[:32]) != coreModule {
		panic("core: governance-wrong-module")
	}
	switch p[32] {
	case actionGuardianSetUpgrade:
		upgrade(v.Digest, p[33:], now, wormholeChainID, replayUntilIndex)
	case actionSetMessageFee:
		setMessageFee(v.Digest, p[33:], wormholeChainID, cur.Address())
	case actionTransferFees:
		transferFees(cur, v.Digest, p[33:], wormholeChainID)
	default:
		// 1, a contract upgrade: Core is never upgraded. 5, a chain-ID
		// recovery: the token bridge handles chain-ID changes.
		panic("core: governance-unsupported-action")
	}
}

// upgrade applies a guardian-set upgrade from the payload after its action
// byte, on Wormhole chain chainID. While the current index is below
// replayUntil, the replaced set is flagged expired (the replay path) instead
// of getting setExpiry seconds (the fresh path).
func upgrade(digest [32]byte, p []byte, now int64, chainID uint16, replayUntil uint32) {
	if len(p) < 2 {
		panic("core: governance-malformed")
	}
	target := uint16(p[0])<<8 | uint16(p[1])
	if target != 0 && target != chainID {
		panic("core: governance-wrong-target-chain")
	}
	body := p[2:]
	if len(body) < 5 || len(body) != 5+20*int(body[4]) {
		panic("core: governance-malformed")
	}
	index := be32(body[:4])
	keys := string(body[5:])
	if reason := checkKeys(keys); reason != "" {
		panic("core: " + reason)
	}
	// Solidity reverts on overflow; Gno wraps, so refuse explicitly.
	if currentIndex == ^uint32(0) || now > int64(^uint32(0)-setExpiry) {
		panic("core: governance-arithmetic-overflow")
	}
	if index != currentIndex+1 {
		panic("core: guardian-set-index-not-next")
	}
	consumed.Set(string(digest[:]), true)
	replaced := guardianSetAt(currentIndex)
	if currentIndex < replayUntil {
		replaced.expired = true
	} else {
		replaced.expirationTime = uint32(now) + setExpiry
	}
	sets.Set(setKey(index), &guardianSet{keys: keys})
	previous := currentIndex
	currentIndex = index
	chain.Emit("GuardianSetUpgraded",
		"old_index", strconv.FormatUint(uint64(previous), 10),
		"new_index", strconv.FormatUint(uint64(index), 10))
}

// setMessageFee applies a SetMessageFee payload after its action byte, on
// Wormhole chain chainID: the target chain, which must be this one, then the
// fee as a 32-byte big-endian integer, which must fit an int64. It records
// Core's ugnot balance at self, its address, so the new fee is paid by what
// arrives from then on.
func setMessageFee(digest [32]byte, p []byte, chainID uint16, self address) {
	if len(p) != 2+32 {
		panic("core: governance-malformed")
	}
	if uint16(p[0])<<8|uint16(p[1]) != chainID {
		panic("core: governance-wrong-target-chain")
	}
	fee, ok := int64Of(p[2:])
	if !ok {
		panic("core: governance-fee-out-of-range")
	}
	consumed.Set(string(digest[:]), true)
	messageFee = fee
	recordedBalance = balance(self)
	chain.Emit("MessageFeeSet", "fee", strconv.FormatInt(fee, 10))
}

// transferFees applies a TransferFees payload after its action byte, on
// Wormhole chain chainID: the target chain, this one or 0, the amount as a
// 32-byte big-endian integer, which must fit an int64, then the recipient, a
// 20-byte gno address left-padded with zeros. It pays the amount in ugnot out
// of Core's balance, through cur.
func transferFees(cur realm, digest [32]byte, p []byte, chainID uint16) {
	if len(p) != 2+32+32 {
		panic("core: governance-malformed")
	}
	if target := uint16(p[0])<<8 | uint16(p[1]); target != 0 && target != chainID {
		panic("core: governance-wrong-target-chain")
	}
	amount, ok := int64Of(p[2:34])
	if !ok {
		panic("core: governance-fee-out-of-range")
	}
	// EVM truncates the recipient to its last 20 bytes; Core refuses one that
	// does not fit them.
	if string(p[34:46]) != zeroKey[:12] {
		panic("core: governance-fee-recipient")
	}
	if amount > balance(cur.Address()) {
		panic("core: governance-payout-exceeds-balance")
	}
	encoded, err := bech32.EncodeFromBase256("g", p[46:])
	if err != nil {
		panic(err)
	}
	recipient := address(encoded)
	consumed.Set(string(digest[:]), true)
	// A node's bank ignores a zero send, but gno's test banker refuses one
	// from an address without coins.
	if amount > 0 {
		banker.NewBanker(banker.BankerTypeRealmSend, cur).SendCoins(cur.Address(), recipient,
			chain.Coins{{feeDenom, amount}})
	}
	// Read again: a payout to Core itself leaves its balance unchanged.
	recordedBalance = balance(cur.Address())
	chain.Emit("FeesTransferred", "recipient", string(recipient), "amount", strconv.FormatInt(amount, 10))
}

// int64Of reads a 32-byte big-endian integer that must fit an int64.
func int64Of(word []byte) (int64, bool) {
	if string(word[:20]) != zeroKey || string(word[20:24]) != zeroKey[:4] || word[24] >= 0x80 {
		return 0, false
	}
	var n int64
	for _, b := range word[24:] {
		n = n<<8 | int64(b)
	}
	return n, true
}
