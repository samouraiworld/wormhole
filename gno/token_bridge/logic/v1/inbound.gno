package logic

import (
	"encoding/hex"

	tb "gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/core"
	vault "gno.land/r/wormhole/tokenbridge"
)

const (
	// inboundDelay is how long a transfer over the inbound budget waits, in
	// seconds.
	inboundDelay = 86400
	// bodyHeaderLen is the length of a VAA body before its payload: timestamp,
	// nonce, emitter chain, emitter, sequence and consistency.
	bodyHeaderLen = 51
	maxInt64      = 1<<63 - 1
)

// Redeem takes a guardian-signed transfer from a registered peer, which anyone
// may present. A payload 1 within the asset's inbound budget is paid at
// once under the relayer-fee rule, with the caller as the redeemer. A payload
// 1 over the budget, and every payload 3, is recorded as a claim: its release
// time is 24 hours later if over the budget, and now otherwise. A transfer
// released now is counted in the window; a delayed one is counted neither now
// nor at its release. The checks run in a fixed order, and the fields they read
// are copied out of the VAA before the first crossing call.
func Redeem(cur realm, raw []byte) {
	gate()
	v := core.VerifyVAA(raw)
	requirePeer(v.EmitterChain, v.EmitterAddress)
	t, err := tb.ParseTransfer(v.Payload)
	fail(err)
	if t.ToChain != core.ChainID() {
		panic("tokenbridge: wrong-target-chain")
	}
	recipient := recipientAddress(t.To)
	if vault.IsRedeemed(v.EmitterChain, hex.EncodeToString(v.EmitterAddress[:]), v.Sequence) {
		panic("tokenbridge: transfer-redeemed")
	}
	a, symbol := inboundAsset(t.Token)
	amount, err := tb.Int64(t.Amount)
	fail(err)
	var fee int64
	if t.PayloadID == 1 {
		fee, err = tb.Int64(t.Fee)
		fail(err)
	}
	now := blockTime()
	hour := now / hourSeconds
	releasedNow := a.inbound.fits(hour, amount, a.inboundBudget)
	if t.PayloadID == 1 && releasedNow {
		redeemer := cur.Previous().Address()
		charged := relayerFee(fee, amount, recipient, redeemer)
		checkPayment(symbol, amount, redeemer, charged)
		vault.MarkRedeemed(cross(cur), v.EmitterChain, v.EmitterAddress, v.Sequence)
		pay(cur, t.Token, symbol, recipient, amount-charged)
		pay(cur, t.Token, symbol, redeemer, charged)
	} else {
		release := now
		if !releasedNow {
			release = now + inboundDelay
		}
		vault.RecordClaim(cross(cur), v.EmitterChain, v.EmitterAddress, v.Sequence, tb.Claim{Digest: v.Digest,
			PayloadID: t.PayloadID, Recipient: recipient, Asset: t.Token, Amount: amount, Fee: fee,
			BodyLen: bodyHeaderLen + len(v.Payload), ReleaseTime: release})
	}
	if releasedNow {
		a.inbound.count(hour, amount)
	}
}

// CompleteClaim completes a released payload-1 claim at the vault, which
// anyone may do once its time comes, and pays it under the relayer-fee rule
// with the caller as the redeemer. The vault re-applies neither the allowlist
// nor the limits.
func CompleteClaim(cur realm, emitterChain uint16, emitterAddress [32]byte, sequence uint64, body []byte) {
	gate()
	vault.CompleteClaim(cross(cur), emitterChain, emitterAddress, sequence, body, cur.Previous().Address())
}

// CreateWrapped creates the wrapped asset an AssetMeta describes, if the asset
// is open on the allowlist, which anyone may present. The token's chain
// must be its emitter's, a hardening beyond upstream, and gno tokens are never
// wrapped. The vault derives the wrapper's name and symbol and keeps
// min(decimals, 8), and it refuses a repeat.
func CreateWrapped(cur realm, raw []byte) {
	gate()
	v := core.VerifyVAA(raw)
	requirePeer(v.EmitterChain, v.EmitterAddress)
	m, err := tb.ParseAssetMeta(v.Payload)
	fail(err)
	if m.Token.Chain == core.ChainID() {
		panic("tokenbridge: asset-meta-native")
	}
	if m.Token.Chain != v.EmitterChain {
		panic("tokenbridge: asset-meta-wrong-emitter")
	}
	openAsset(m.Token)
	vault.CreateWrapped(cross(cur), m, v.Digest)
}

// requirePeer requires a VAA's emitter to be its chain's registered peer.
func requirePeer(emitterChain uint16, emitter [32]byte) {
	if vault.Peer(emitterChain) != hex.EncodeToString(emitter[:]) {
		panic("tokenbridge: unregistered-emitter")
	}
}

// recipientAddress reads a transfer's 32-byte recipient, whose first 12 bytes
// must be zero, as a gno address.
func recipientAddress(to [32]byte) address {
	for _, c := range to[:12] {
		if c != 0 {
			panic("tokenbridge: recipient-high-bytes")
		}
	}
	return encodeAddress(to[12:])
}

// inboundAsset resolves the asset a transfer names. It returns the limits and the wrapper's
// symbol of the asset a transfer names: GNOT, whose symbol is "", or a wrapped
// asset that exists and is open on the allowlist, not exit-only. The allowlist
// comes before the limits, so a refused transfer records nothing and consumes
// no replay key.
func inboundAsset(token tb.Origin) (*asset, string) {
	if token.Chain == core.ChainID() {
		if token.Address != tb.GNOTAddress() {
			panic("tokenbridge: unknown-native-token")
		}
		return gnot, ""
	}
	symbol := vault.WrappedSymbol(token.Chain, hex.EncodeToString(token.Address[:]))
	if symbol == "" {
		panic("tokenbridge: wrapped-not-found")
	}
	return openAsset(token), symbol
}

// relayerFee applies the relayer-fee rule: a fee is charged only when
// it is non-zero and the redeemer is not the recipient, and then must not
// exceed the amount.
func relayerFee(fee, amount int64, recipient, redeemer address) int64 {
	if fee == 0 || redeemer == recipient {
		return 0
	}
	if fee > amount {
		panic("tokenbridge: fee-exceeds-amount")
	}
	return fee
}

// checkPayment runs the payment checks that the vault's Release and
// Mint repeat, before the first write: the escrow covers a GNOT amount, a
// wrapper's supply can grow by its amount, and a redeemer the fee pays is an
// address the bank and grc20 pay, which only a query can fail.
func checkPayment(symbol string, amount int64, redeemer address, charged int64) {
	if symbol == "" {
		if amount > vault.LockedGNOT() {
			panic("tokenbridge: locked-insufficient")
		}
	} else if amount > maxInt64-vault.TotalSupply(symbol) {
		panic("tokenbridge: supply-overflow")
	}
	if charged > 0 && (len(redeemer) != 40 || !redeemer.IsValid()) {
		panic("tokenbridge: caller-address-malformed")
	}
}

// pay pays a share of a transfer: GNOT out of escrow when symbol is "", else
// the wrapped asset, minted. A zero share sends and mints nothing.
func pay(cur realm, token tb.Origin, symbol string, to address, amount int64) {
	if symbol == "" {
		vault.Release(cross(cur), to, amount)
	} else {
		vault.Mint(cross(cur), token, to, amount)
	}
}
