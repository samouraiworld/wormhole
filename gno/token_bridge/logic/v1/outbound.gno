package logic

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"chain/runtime/unsafe"

	tb "gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/core"
	vault "gno.land/r/wormhole/tokenbridge"
)

// The outbound entry points. Each applies the gate, then its caller
// rules: GNOT leaves only on a direct user call, and a direct user attaches
// exactly the GNOT amount and Core's message fee, in ugnot only, which this
// realm forwards. A realm sender of a wrapped asset has paid Core itself, and
// what the origin call attached is not read. Then the transfer's checks, the
// asset's outbound limits, the sends, and the vault's operation, which locks or
// burns the amount and publishes the message. The amount is counted last.
//
// runtime.AssertOriginCall counts the call frames above it and accepts only
// the entry point's own, so each entry point calls it in its own body, never
// through a helper.

const corePath = "gno.land/r/wormhole/core"

// TransferGNOT sends amount ugnot to recipient on recipientChain, with a relayer
// fee of fee, and returns Core's sequence. The caller must be a user calling it
// directly, attaching amount plus Core's message fee.
func TransferGNOT(cur realm, amount int64, recipientChain uint16, recipient [32]byte, fee int64,
	nonce uint32,
) uint64 {
	gate()
	if !cur.Previous().IsUserCall() {
		panic("tokenbridge: deposit-not-user-call")
	}
	runtime.AssertOriginCall()
	messageFee := gnotAttached(amount)
	requireTarget(recipientChain)
	checkFee(amount, fee)
	hour := currentHour()
	checkOutbound(gnot, hour, amount)
	forward(cur, messageFee, amount)
	seq := vault.LockAndPublish(cross(cur), cur.Previous().Address(), amount, recipientChain, recipient, fee, nonce)
	gnot.outbound.count(hour, amount)
	return seq
}

// TransferGNOTWithPayload is TransferGNOT for payload 3, carrying payload for
// the recipient's contract, from the caller's 20 bytes.
func TransferGNOTWithPayload(cur realm, amount int64, recipientChain uint16, recipient [32]byte, payload []byte,
	nonce uint32,
) uint64 {
	gate()
	if !cur.Previous().IsUserCall() {
		panic("tokenbridge: deposit-not-user-call")
	}
	runtime.AssertOriginCall()
	messageFee := gnotAttached(amount)
	requireTarget(recipientChain)
	checkPayload(payload)
	hour := currentHour()
	checkOutbound(gnot, hour, amount)
	forward(cur, messageFee, amount)
	seq := vault.LockAndPublishWithPayload(cross(cur), cur.Previous().Address(), amount, recipientChain, recipient,
		payload, nonce)
	gnot.outbound.count(hour, amount)
	return seq
}

// TransferWrapped sends amount of the wrapped token symbol, burned from the
// caller, to recipient on recipientChain, with a relayer fee of fee, and returns
// Core's sequence. A user calling it directly attaches Core's message fee; a
// realm pays Core itself first.
func TransferWrapped(cur realm, symbol string, amount int64, recipientChain uint16, recipient [32]byte, fee int64,
	nonce uint32,
) uint64 {
	gate()
	var messageFee int64
	if cur.Previous().IsUserCall() {
		runtime.AssertOriginCall()
		messageFee = feeAttached()
	}
	origin, a := wrappedTransfer(symbol, amount, recipientChain)
	checkFee(amount, fee)
	hour := currentHour()
	checkOutbound(a, hour, amount)
	forward(cur, messageFee, 0)
	seq := vault.BurnAndPublish(cross(cur), origin, cur.Previous().Address(), amount, recipientChain, recipient, fee,
		nonce)
	a.outbound.count(hour, amount)
	return seq
}

// TransferWrappedWithPayload is TransferWrapped for payload 3, carrying payload
// for the recipient's contract, from the caller's 20 bytes.
func TransferWrappedWithPayload(cur realm, symbol string, amount int64, recipientChain uint16, recipient [32]byte,
	payload []byte, nonce uint32,
) uint64 {
	gate()
	var messageFee int64
	if cur.Previous().IsUserCall() {
		runtime.AssertOriginCall()
		messageFee = feeAttached()
	}
	origin, a := wrappedTransfer(symbol, amount, recipientChain)
	checkPayload(payload)
	hour := currentHour()
	checkOutbound(a, hour, amount)
	forward(cur, messageFee, 0)
	seq := vault.BurnAndPublishWithPayload(cross(cur), origin, cur.Previous().Address(), amount, recipientChain,
		recipient, payload, nonce)
	a.outbound.count(hour, amount)
	return seq
}

// AttestGNOT publishes GNOT's AssetMeta from the vault's configuration, so that
// peers can create wrapped GNOT, and returns Core's sequence. Anyone may call
// it, paying Core's message fee as a wrapped transfer does.
func AttestGNOT(cur realm, nonce uint32) uint64 {
	gate()
	var messageFee int64
	if cur.Previous().IsUserCall() {
		runtime.AssertOriginCall()
		messageFee = feeAttached()
	}
	forward(cur, messageFee, 0)
	return vault.PublishGNOTMeta(cross(cur), nonce)
}

// gnotAttached checks the attachment for GNOT: the origin call attached
// ugnot only, the amount is positive, and the attachment is exactly the amount
// plus Core's message fee, which it returns to forward.
func gnotAttached(amount int64) int64 {
	attached := attachedUgnot()
	if amount <= 0 {
		panic("tokenbridge: zero-amount")
	}
	messageFee := core.MessageFee()
	requireAttached(attached, amount, messageFee)
	return messageFee
}

// feeAttached applies a direct user's rule when it sends no GNOT: the origin
// call attached exactly Core's message fee, in ugnot only, which it returns to
// forward. A realm sender, a maketx run script among them, has paid Core
// itself, and what the origin call attached is not read.
func feeAttached() int64 {
	attached := attachedUgnot()
	messageFee := core.MessageFee()
	requireAttached(attached, 0, messageFee)
	return messageFee
}

// wrappedTransfer checks a wrapped transfer: the symbol names a wrapped
// asset, the amount is positive and the target registered. It returns the
// asset's origin and its limits, nil for a wrapped asset neither open nor
// exit-only on the allowlist.
func wrappedTransfer(symbol string, amount int64, recipientChain uint16) (tb.Origin, *asset) {
	tokenChain, tokenHex, found := vault.Origin(symbol)
	if !found {
		panic("tokenbridge: wrapped-not-found")
	}
	if amount <= 0 {
		panic("tokenbridge: zero-amount")
	}
	requireTarget(recipientChain)
	token, _ := hex32(tokenHex) // the vault's own hex of a 32-byte address
	origin := tb.Origin{Chain: tokenChain, Address: token}
	return origin, assetOf(origin)
}

// attachedUgnot returns what the origin call attached, which must be ugnot
// only. Only a direct user call reads it, behind the deposit guards.
func attachedUgnot() int64 {
	sent := unsafe.OriginSend()
	for _, c := range sent {
		if c.Denom != "ugnot" {
			panic("tokenbridge: non-ugnot-coins")
		}
	}
	return sent.AmountOf("ugnot")
}

// requireAttached requires the attachment to be exactly amount plus the
// message fee. Neither the attachment nor Core's fee is ever negative, so
// attached - messageFee cannot wrap, where amount + messageFee could.
func requireAttached(attached, amount, messageFee int64) {
	if attached-messageFee != amount {
		panic("tokenbridge: attached-amount-mismatch")
	}
}

// requireTarget requires a registered peer on recipientChain, which excludes
// chain 0 and gno.
func requireTarget(recipientChain uint16) {
	if vault.Peer(recipientChain) == "" {
		panic("tokenbridge: unregistered-target")
	}
}

// checkFee checks payload 1's relayer fee against the amount: 0 <= fee <=
// amount, since the wire field is an unsigned uint256.
func checkFee(amount, fee int64) {
	if fee < 0 {
		panic("tokenbridge: amount-out-of-range")
	}
	if fee > amount {
		panic("tokenbridge: fee-exceeds-amount")
	}
}

// checkPayload checks that payload 3's bytes fit Core's 2048-byte cap less
// payload 3's 133-byte header.
func checkPayload(payload []byte) {
	if len(payload) > tb.MaxTransferPayload {
		panic("tokenbridge: payload-too-large")
	}
}

// checkOutbound applies an asset's outbound limits: the
// per-transfer cap, then the window cap. A wrapped asset neither open nor
// exit-only on the allowlist has none, and fails with not-allowlisted. Nothing
// is counted here.
func checkOutbound(a *asset, hour, amount int64) {
	if a == nil {
		panic("tokenbridge: not-allowlisted")
	}
	if amount > a.perTransfer || !a.outbound.fits(hour, amount, a.outboundCap) {
		panic("tokenbridge: outbound-cap")
	}
}

// forward sends the message fee to Core and a GNOT amount to the vault, out of
// what the direct user attached to this realm. A zero sends nothing.
func forward(cur realm, messageFee, amount int64) {
	send := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	if messageFee > 0 {
		send.SendCoins(cur.Address(), chain.PackageAddress(corePath), chain.NewCoins(chain.NewCoin("ugnot", messageFee)))
	}
	if amount > 0 {
		send.SendCoins(cur.Address(), chain.PackageAddress(vaultPath), chain.NewCoins(chain.NewCoin("ugnot", amount)))
	}
}
