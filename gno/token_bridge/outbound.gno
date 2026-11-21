package tokenbridge

import (
	"chain"
	"encoding/hex"
	"strconv"

	"gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/core"
)

// The outbound operations: each locks or burns its amount and
// publishes a transfer of exactly that amount, built here, in one call. So
// whatever the current logic does, every transfer under the vault's emitter
// is backed at its publication. Each is logic-only and value-gated, and
// returns Core's sequence.

// LockAndPublish locks amount ugnot, which the logic sent the vault earlier
// in the transaction, and publishes payload 1 to a registered peer.
func LockAndPublish(cur realm, sender address, amount int64, recipientChain uint16, recipient [32]byte,
	fee int64, nonce uint32,
) uint64 {
	requireLogic(cur)
	gate()
	checkTarget(amount, recipientChain)
	checkFee(amount, fee)
	checkSender(sender) // the event names it
	b := checkLock(cur, amount)
	p, err := tokenbridge.EncodeTransfer(amount, gnotOrigin(), recipient, recipientChain, fee)
	fail(err)
	seq := core.PublishMessage(cross(cur), nonce, p, 1)
	lockedGNOT += amount
	recordedBalance = b
	transferOut(gnotOrigin(), amount, sender, seq)
	lapse()
	return seq
}

// LockAndPublishWithPayload is LockAndPublish for payload 3, whose
// fromAddress is sender's 20 bytes, left-padded.
func LockAndPublishWithPayload(cur realm, sender address, amount int64, recipientChain uint16,
	recipient [32]byte, payload []byte, nonce uint32,
) uint64 {
	requireLogic(cur)
	gate()
	checkTarget(amount, recipientChain)
	from := checkPayload(sender, payload)
	b := checkLock(cur, amount)
	p, err := tokenbridge.EncodeTransferWithPayload(amount, gnotOrigin(), recipient, recipientChain, from, payload)
	fail(err)
	seq := core.PublishMessage(cross(cur), nonce, p, 1)
	lockedGNOT += amount
	recordedBalance = b
	transferOut(gnotOrigin(), amount, sender, seq)
	lapse()
	return seq
}

// BurnAndPublish burns amount of the wrapped asset with this origin from
// from, the account debited and the message's sender, and publishes payload
// 1 naming the asset's recorded origin.
func BurnAndPublish(cur realm, origin tokenbridge.Origin, from address, amount int64, recipientChain uint16,
	recipient [32]byte, fee int64, nonce uint32,
) uint64 {
	requireLogic(cur)
	gate()
	checkTarget(amount, recipientChain)
	checkFee(amount, fee)
	checkSender(from) // the event names it
	w := checkBurn(origin, from, amount)
	p, err := tokenbridge.EncodeTransfer(amount, w.origin, recipient, recipientChain, fee)
	fail(err)
	seq := core.PublishMessage(cross(cur), nonce, p, 1)
	burn(w, from, amount)
	transferOut(w.origin, amount, from, seq)
	lapse()
	return seq
}

// BurnAndPublishWithPayload is BurnAndPublish for payload 3, whose
// fromAddress is from's 20 bytes, left-padded.
func BurnAndPublishWithPayload(cur realm, origin tokenbridge.Origin, from address, amount int64,
	recipientChain uint16, recipient [32]byte, payload []byte, nonce uint32,
) uint64 {
	requireLogic(cur)
	gate()
	checkTarget(amount, recipientChain)
	sender := checkPayload(from, payload)
	w := checkBurn(origin, from, amount)
	p, err := tokenbridge.EncodeTransferWithPayload(amount, w.origin, recipient, recipientChain, sender, payload)
	fail(err)
	seq := core.PublishMessage(cross(cur), nonce, p, 1)
	burn(w, from, amount)
	transferOut(w.origin, amount, from, seq)
	lapse()
	return seq
}

// PublishGNOTMeta publishes GNOT's AssetMeta, built from the configuration:
// GNOT's token address, gno's chain, decimals 6, and gnotSymbol and
// gnotName, each zero-padded to 32 bytes. It emits no event.
func PublishGNOTMeta(cur realm, nonce uint32) uint64 {
	requireLogic(cur)
	gate()
	seq := core.PublishMessage(cross(cur), nonce, gnotMeta(), 1)
	lapse()
	return seq
}

func gnotMeta() []byte {
	symbol, _ := tokenbridge.Pad32(gnotSymbol) // init checked both strings
	name, _ := tokenbridge.Pad32(gnotName)
	return tokenbridge.EncodeAssetMeta(tokenbridge.AssetMeta{Token: gnotOrigin(), Decimals: gnotDecimals,
		Symbol: symbol, Name: name})
}

// checkTarget checks a positive amount and a target chain with a peer, which
// excludes chain 0 and gno.
func checkTarget(amount int64, recipientChain uint16) {
	if amount <= 0 {
		panic("tokenbridge: zero-amount")
	}
	if !peers.Has(chainKey(recipientChain)) {
		panic("tokenbridge: unregistered-target")
	}
}

// checkFee checks payload 1's relayer fee: 0 <= fee <= amount.
func checkFee(amount, fee int64) {
	if fee < 0 {
		panic("tokenbridge: amount-out-of-range")
	}
	if fee > amount {
		panic("tokenbridge: fee-exceeds-amount")
	}
}

// checkPayload checks payload 3's bytes against Core's cap and returns its
// sender's 20 bytes, left-padded.
func checkPayload(sender address, payload []byte) [32]byte {
	if len(payload) > tokenbridge.MaxTransferPayload {
		panic("tokenbridge: payload-too-large")
	}
	return padded(checkSender(sender))
}

// checkSender requires the address a transfer's event names, and payload 3
// carries, to be well formed: its bech32 or bech32m checksum holds, as the
// payee checks require. Its 20 bytes are decoded first, which also
// bounds the length before the checksummed decode. Only a faulty logic passes
// anything else.
func checkSender(a address) [20]byte {
	b := addressBytes(a)
	if !a.IsValid() {
		panic("tokenbridge: caller-address-malformed")
	}
	return b
}

// checkLock checks that ugnot arrived for amount since the last GNOT
// operation, and returns the vault's balance.
func checkLock(cur realm, amount int64) int64 {
	b := balanceOf(cur.Address())
	if b < recordedBalance || b-recordedBalance < amount {
		panic("tokenbridge: lock-unfunded")
	}
	if lockedGNOT > maxInt64-amount {
		panic("tokenbridge: amount-out-of-range")
	}
	return b
}

// checkBurn checks that the wrapped asset exists and that from holds
// amount, and returns the asset.
func checkBurn(origin tokenbridge.Origin, from address, amount int64) *wrappedAsset {
	w := wrappedAt(origin.Key())
	if w == nil {
		panic("tokenbridge: wrapped-not-found")
	}
	if w.token.BalanceOf(from) < amount {
		panic("tokenbridge: burn-exceeds-balance")
	}
	return w
}

// burn burns what checkBurn allowed, so the ledger has nothing to refuse.
func burn(w *wrappedAsset, from address, amount int64) {
	if err := w.ledger.Burn(from, amount); err != nil {
		panic("tokenbridge: wrapped-ledger-error")
	}
}

func transferOut(o tokenbridge.Origin, amount int64, sender address, seq uint64) {
	chain.Emit("WormholeTransferOut",
		"token_chain", strconv.Itoa(int(o.Chain)),
		"token_address", hex.EncodeToString(o.Address[:]),
		"amount", strconv.FormatInt(amount, 10),
		"sender", string(sender),
		"sequence", strconv.FormatUint(seq, 10))
}
