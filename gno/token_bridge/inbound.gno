package tokenbridge

import (
	"chain"
	"chain/banker"
	"encoding/hex"
	"strconv"

	"gno.land/p/nt/grc20/v0"
	"gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/nt/grc20reg/v0"
)

// The inbound and claim operations. Each is logic-only and
// value-gated, except CancelClaim, which requires a pause. The vault trusts
// the current logic for whom they pay and which transfers they record; it
// still never records a replay key twice, completes a claim twice or after
// it was cancelled, or releases more GNOT than is locked.

// Release moves amount ugnot out of escrow to to. A zero amount sends
// nothing.
func Release(cur realm, to address, amount int64) {
	requireLogic(cur)
	gate()
	checkRelease(amount)
	if amount > 0 {
		requirePayee(to)
	}
	release(cur, to, amount)
	recordedBalance = balanceOf(cur.Address())
	lapse()
}

// Mint mints amount of the wrapped asset with this origin to to. A zero
// amount mints nothing.
func Mint(cur realm, origin tokenbridge.Origin, to address, amount int64) {
	requireLogic(cur)
	gate()
	w := wrappedAt(origin.Key())
	if w == nil {
		panic("tokenbridge: wrapped-not-found")
	}
	mint(w, to, amount)
	lapse()
}

// MarkRedeemed records a transfer's replay key, for a transfer the logic
// pays at once.
func MarkRedeemed(cur realm, emitterChain uint16, emitterAddress [32]byte, sequence uint64) {
	requireLogic(cur)
	gate()
	key := tokenbridge.ReplayKey(emitterChain, emitterAddress, sequence)
	if redeemed.Has(key) {
		panic("tokenbridge: transfer-redeemed")
	}
	redeemed.Set(key, true)
	transferEvent("TransferRedeemed", emitterChain, emitterAddress[:], sequence)
	lapse()
}

// RecordClaim records a copy of c as an open claim and marks its replay key
// redeemed. The claim is delayed if its release time is later than the
// block time.
func RecordClaim(cur realm, emitterChain uint16, emitterAddress [32]byte, sequence uint64, c tokenbridge.Claim) {
	requireLogic(cur)
	gate()
	key := tokenbridge.ReplayKey(emitterChain, emitterAddress, sequence)
	if redeemed.Has(key) {
		panic("tokenbridge: transfer-redeemed")
	}
	claims.Set(key, &claim{
		digest:      c.Digest,
		payloadID:   c.PayloadID,
		recipient:   c.Recipient,
		asset:       c.Asset,
		amount:      c.Amount,
		fee:         c.Fee,
		bodyLen:     c.BodyLen,
		releaseTime: c.ReleaseTime,
		delayed:     c.ReleaseTime > blockTime(),
	})
	redeemed.Set(key, true)
	transferEvent("TransferRedeemed", emitterChain, emitterAddress[:], sequence)
	chain.Emit("ClaimRecorded",
		"emitter_chain", strconv.Itoa(int(emitterChain)),
		"emitter_address", hex.EncodeToString(emitterAddress[:]),
		"sequence", strconv.FormatUint(sequence, 10),
		"release_time", strconv.FormatInt(c.ReleaseTime, 10))
	lapse()
}

// CompleteClaim completes a released payload-1 claim whose body is body, and
// pays it under the relayer-fee rule with redeemer as the redeemer. It
// re-applies neither the allowlist nor the limits.
func CompleteClaim(cur realm, emitterChain uint16, emitterAddress [32]byte, sequence uint64, body []byte,
	redeemer address,
) {
	requireLogic(cur)
	gate()
	c := openClaim(tokenbridge.ReplayKey(emitterChain, emitterAddress, sequence), 1)
	requireReleased(c)
	if doubleKeccak(body) != c.digest {
		panic("tokenbridge: claim-body-mismatch")
	}
	fee := relayerFee(c, redeemer)
	w := checkPayment(c.asset, c.amount)
	// Each payee must be payable before the claim is marked completed.
	if c.amount-fee > 0 {
		requirePayee(c.recipient)
	}
	if fee > 0 {
		requirePayee(redeemer)
	}
	c.state = claimCompleted
	pay(cur, w, c.recipient, c.amount-fee)
	pay(cur, w, redeemer, fee)
	transferEvent("ClaimCompleted", emitterChain, emitterAddress[:], sequence)
	lapse()
}

// CancelClaim cancels a delayed, open claim. It runs only while paused, and
// never under the chain-ID freeze. Nothing is paid: the replay key stays
// redeemed, and a GNOT claim's amount stays locked.
func CancelClaim(cur realm, emitterChain uint16, emitterAddress [32]byte, sequence uint64) {
	requireLogic(cur)
	requireBound()
	if !paused {
		panic("tokenbridge: not-paused")
	}
	c := claimAt(tokenbridge.ReplayKey(emitterChain, emitterAddress, sequence))
	if c == nil {
		panic("tokenbridge: claim-not-found")
	}
	if !c.delayed {
		panic("tokenbridge: claim-not-delayed")
	}
	requireOpen(c)
	c.state = claimCancelled
	transferEvent("ClaimCancelled", emitterChain, emitterAddress[:], sequence)
	lapse()
}

// CreateWrapped creates the wrapped asset for meta's origin, under the name
// and symbol of the naming rules, and registers it in grc20reg. The logic has checked
// that meta is authentic and allowlisted; digest is its AssetMeta's.
func CreateWrapped(cur realm, meta tokenbridge.AssetMeta, digest [32]byte) {
	requireLogic(cur)
	gate()
	// No wrapper, and so no burn, can stand for GNOT or any gno token.
	if meta.Token.Chain == wormholeChainID {
		panic("tokenbridge: asset-meta-native")
	}
	key := meta.Token.Key()
	if wrapped.Has(key) {
		panic("tokenbridge: wrapped-exists")
	}
	symbol := wrappedSymbol(meta)
	token, ledger := grc20.NewToken(tokenbridge.WrappedName(meta), symbol,
		int(tokenbridge.WrapperDecimals(meta.Decimals)), tokenIDs.Next(), cur)
	grc20reg.Register(cross(cur), token, "")
	wrapped.Set(key, &wrappedAsset{origin: meta.Token, token: token, ledger: ledger, meta: digest})
	originBySymbol.Set(symbol, key)
	chain.Emit("WrappedCreated",
		"token_chain", strconv.Itoa(int(meta.Token.Chain)),
		"token_address", hex.EncodeToString(meta.Token.Address[:]),
		"symbol", symbol,
		"token_id", token.ID())
	lapse()
}

// wrappedSymbol is the AssetMeta's symbol if grc20 accepts it and no wrapper
// uses it, and otherwise the first unused WH<n>.
func wrappedSymbol(meta tokenbridge.AssetMeta) string {
	if s := tokenbridge.String32(meta.Symbol); tokenbridge.ValidSymbol(s) && !originBySymbol.Has(s) {
		return s
	}
	for n := 1; ; n++ {
		if s := tokenbridge.FallbackSymbol(n); !originBySymbol.Has(s) {
			return s
		}
	}
}

func requireReleased(c *claim) {
	if blockTime() < c.releaseTime {
		panic("tokenbridge: claim-not-released")
	}
}

// relayerFee applies the relayer-fee rule: a fee is charged only when
// it is non-zero and the redeemer is not the recipient, and then must not
// exceed the amount.
func relayerFee(c *claim, redeemer address) int64 {
	if c.fee == 0 || redeemer == c.recipient {
		return 0
	}
	if c.fee < 0 {
		panic("tokenbridge: amount-out-of-range")
	}
	if c.fee > c.amount {
		panic("tokenbridge: fee-exceeds-amount")
	}
	return c.fee
}

// checkPayment runs a payment's checks before any write: the
// amount is not negative; for GNOT it is at most the escrow, and for a
// wrapped asset the asset exists and its supply can grow by it. It returns
// the wrapped asset, or nil for GNOT.
func checkPayment(asset tokenbridge.Origin, amount int64) *wrappedAsset {
	if amount < 0 {
		panic("tokenbridge: amount-out-of-range")
	}
	if isGNOT(asset) {
		checkRelease(amount)
		return nil
	}
	w := wrappedAt(asset.Key())
	if w == nil {
		panic("tokenbridge: wrapped-not-found")
	}
	if amount > maxInt64-w.token.TotalSupply() {
		panic("tokenbridge: supply-overflow")
	}
	return w
}

// requirePayee refuses an address that neither the bank nor grc20 would
// pay, which only a faulty logic could name. The length check bounds the
// checksummed decode.
func requirePayee(a address) {
	if len(a) != 40 || !a.IsValid() {
		panic("tokenbridge: caller-address-malformed")
	}
}

func checkRelease(amount int64) {
	if amount < 0 {
		panic("tokenbridge: amount-out-of-range")
	}
	if amount > lockedGNOT {
		panic("tokenbridge: locked-insufficient")
	}
}

// pay pays a share that checkPayment allowed: GNOT from escrow when w is
// nil, else the wrapped asset, minted.
func pay(cur realm, w *wrappedAsset, to address, amount int64) {
	if w == nil {
		release(cur, to, amount)
		recordedBalance = balanceOf(cur.Address())
		return
	}
	mint(w, to, amount)
}

// release sends amount ugnot from escrow; a zero amount sends nothing, since
// gno's test banker refuses a zero send from an empty balance.
func release(cur realm, to address, amount int64) {
	if amount > 0 {
		banker.NewBanker(banker.BankerTypeRealmSend, cur).SendCoins(cur.Address(), to,
			chain.NewCoins(chain.NewCoin("ugnot", amount)))
	}
	lockedGNOT -= amount
}

// mint mints amount of w to to; a zero amount mints nothing, so it emits no
// grc20 event. The ledger returns errors rather than panicking.
func mint(w *wrappedAsset, to address, amount int64) {
	if amount == 0 {
		return
	}
	if err := w.ledger.Mint(to, amount); err != nil {
		if err == grc20.ErrMintOverflow {
			panic("tokenbridge: supply-overflow")
		}
		panic("tokenbridge: wrapped-ledger-error")
	}
}

// transferEvent emits an event naming a transfer by its emitter chain,
// emitter and sequence.
func transferEvent(typ string, emitterChain uint16, emitterAddress []byte, sequence uint64) {
	chain.Emit(typ,
		"emitter_chain", strconv.Itoa(int(emitterChain)),
		"emitter_address", hex.EncodeToString(emitterAddress),
		"sequence", strconv.FormatUint(sequence, 10))
}
