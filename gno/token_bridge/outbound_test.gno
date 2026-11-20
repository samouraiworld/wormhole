package tokenbridge

import (
	"strings"
	"testing"

	"gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/core"
)

// registerPeers registers chain 2, and chain 3 through a VAA targeting every
// chain.
func registerPeers(cur realm, t *testing.T) {
	t.Helper()
	for _, name := range []string{"register-2", "register-3-every-chain"} {
		if got := abort(func() { RegisterChain(cross(cur), vaa(t, name)) }); got != "" {
			t.Fatalf("%s: %q", name, got)
		}
	}
}

// TestLockAndPublish locks funded GNOT and publishes it. The amount
// must have arrived since the last GNOT operation: a short balance fails with
// lock-unfunded and changes nothing, and coins sent outside a lock are
// absorbed by the next one, never funding a later lock.
func TestLockAndPublish(cur realm, t *testing.T) {
	reset()
	registerPeers(cur, t)
	emitter := vaultEmitter()
	next := core.NextSequence(emitter)
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	fund(999)
	if got := abort(func() { LockAndPublish(cross(cur), testUser, 1000, 2, testRecipient, 10, 0) }); got != "lock-unfunded" {
		t.Errorf("999 of 1,000 sent: %q", got)
	}
	if LockedGNOT() != 0 || core.NextSequence(emitter) != next {
		t.Errorf("an unfunded lock wrote: locked %d, next sequence %d", LockedGNOT(), core.NextSequence(emitter))
	}
	fund(1)
	var seq uint64
	if got := abort(func() { seq = LockAndPublish(cross(cur), testUser, 1000, 2, testRecipient, 10, 0) }); got != "" {
		t.Fatalf("funded lock: %q", got)
	}
	if seq != next || core.NextSequence(emitter) != next+1 {
		t.Errorf("sequence %d, next %d, want %d", seq, core.NextSequence(emitter), next)
	}
	if LockedGNOT() != 1000 || recordedBalance != ugnot(vaultAddress()) {
		t.Errorf("locked %d, recorded %d of %d", LockedGNOT(), recordedBalance, ugnot(vaultAddress()))
	}
	if got := abort(func() { LockAndPublish(cross(cur), testUser, 1, 2, testRecipient, 0, 0) }); got != "lock-unfunded" {
		t.Errorf("a lock with nothing sent: %q", got)
	}
	// 7 sent for a lock of 5: the 2 extra are absorbed, and fund nothing.
	fund(7)
	if got := abort(func() { LockAndPublish(cross(cur), testUser, 5, 3, testRecipient, 0, 1) }); got != "" {
		t.Fatalf("lock of 5: %q", got)
	}
	if got := abort(func() { LockAndPublish(cross(cur), testUser, 2, 3, testRecipient, 0, 2) }); got != "lock-unfunded" {
		t.Errorf("a donation funded a lock: %q", got)
	}
	if LockedGNOT() != 1005 {
		t.Errorf("locked %d", LockedGNOT())
	}
	// Payload 3 locks the same way.
	fund(4)
	if got := abort(func() { LockAndPublishWithPayload(cross(cur), testUser, 4, 2, testRecipient, []byte("hi"), 3) }); got != "" {
		t.Errorf("payload 3: %q", got)
	}
	if LockedGNOT() != 1009 || core.NextSequence(emitter) != next+3 {
		t.Errorf("payload 3: locked %d, next sequence %d", LockedGNOT(), core.NextSequence(emitter))
	}
	// Its coins fund nothing else: the next lock needs coins of its own.
	if got := abort(func() { LockAndPublish(cross(cur), testUser, 1, 2, testRecipient, 0, 4) }); got != "lock-unfunded" {
		t.Errorf("a lock after payload 3, with nothing sent: %q", got)
	}
	if recordedBalance != ugnot(vaultAddress()) {
		t.Errorf("recorded %d of %d", recordedBalance, ugnot(vaultAddress()))
	}
}

// TestOutboundChecks refuses transfers the vault cannot back, each with
// nothing locked, burned or published, in the logic's order: the amount, the
// target's peer, then payload 1's fee or payload 3's size and sender, then
// the funding.
func TestOutboundChecks(cur realm, t *testing.T) {
	reset()
	registerPeers(cur, t)
	emitter := vaultEmitter()
	next := core.NextSequence(emitter)
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	fund(100)
	big := make([]byte, tokenbridge.MaxTransferPayload+1)
	for _, c := range []struct {
		name, reason string
		fn           func()
	}{
		{"fee above the amount", "fee-exceeds-amount",
			func() { LockAndPublish(cross(cur), testUser, 10, 2, testRecipient, 11, 0) }},
		{"negative fee", "amount-out-of-range",
			func() { LockAndPublish(cross(cur), testUser, 10, 2, testRecipient, -1, 0) }},
		{"chain without a peer", "unregistered-target",
			func() { LockAndPublish(cross(cur), testUser, 10, 4, testRecipient, 0, 0) }},
		{"chain 0", "unregistered-target",
			func() { LockAndPublish(cross(cur), testUser, 10, 0, testRecipient, 0, 0) }},
		{"gno's chain", "unregistered-target",
			func() { LockAndPublish(cross(cur), testUser, 10, wormholeChainID, testRecipient, 0, 0) }},
		{"1,916-byte payload", "payload-too-large",
			func() { LockAndPublishWithPayload(cross(cur), testUser, 10, 2, testRecipient, big, 0) }},
		{"zero amount", "zero-amount",
			func() { LockAndPublish(cross(cur), testUser, 0, 2, testRecipient, 0, 0) }},
		{"negative amount", "zero-amount",
			func() { LockAndPublish(cross(cur), testUser, -5, 2, testRecipient, 0, 0) }},
		{"payload 3 from a malformed sender", "caller-address-malformed",
			func() { LockAndPublishWithPayload(cross(cur), "", 10, 2, testRecipient, nil, 0) }},
		{"payload 1 from a sender whose checksum is wrong", "caller-address-malformed",
			func() { LockAndPublish(cross(cur), badChecksum(), 10, 2, testRecipient, 0, 0) }},
		{"payload 3 from a sender whose checksum is wrong", "caller-address-malformed",
			func() { LockAndPublishWithPayload(cross(cur), badChecksum(), 10, 2, testRecipient, nil, 0) }},
		{"a wrapped payload 1 from a sender whose checksum is wrong", "caller-address-malformed",
			func() { BurnAndPublish(cross(cur), origin(2, 0x99), badChecksum(), 10, 2, testRecipient, 0, 0) }},
		{"payload 1 from a malformed sender", "caller-address-malformed",
			func() { LockAndPublish(cross(cur), "not-an-address", 10, 2, testRecipient, 0, 0) }},
		{"a wrapped payload 1 from a malformed sender", "caller-address-malformed",
			func() { BurnAndPublish(cross(cur), origin(2, 0x99), "not-an-address", 10, 2, testRecipient, 0, 0) }},
		// Two faults: the earlier check decides.
		{"zero amount to a chain without a peer", "zero-amount",
			func() { LockAndPublish(cross(cur), testUser, 0, 4, testRecipient, -1, 0) }},
		{"bad fee to a chain without a peer", "unregistered-target",
			func() { LockAndPublish(cross(cur), testUser, 10, 4, testRecipient, 11, 0) }},
		{"bad fee, unfunded", "fee-exceeds-amount",
			func() { LockAndPublish(cross(cur), testUser, 1000, 2, testRecipient, 1001, 0) }},
		{"oversized payload from a malformed sender, unfunded", "payload-too-large",
			func() { LockAndPublishWithPayload(cross(cur), "", 1000, 2, testRecipient, big, 0) }},
		{"malformed sender, unfunded", "caller-address-malformed",
			func() { LockAndPublishWithPayload(cross(cur), "", 1000, 2, testRecipient, nil, 0) }},
		{"payload 3, unfunded", "lock-unfunded",
			func() { LockAndPublishWithPayload(cross(cur), testUser, 1000, 2, testRecipient, []byte("hi"), 0) }},
		{"wrapped: bad fee for an unknown asset", "fee-exceeds-amount",
			func() { BurnAndPublish(cross(cur), origin(2, 0x99), testUser, 10, 2, testRecipient, 11, 0) }},
		{"wrapped: oversized payload for an unknown asset", "payload-too-large",
			func() { BurnAndPublishWithPayload(cross(cur), origin(2, 0x99), testUser, 10, 2, testRecipient, big, 0) }},
	} {
		if got := abort(c.fn); got != c.reason {
			t.Errorf("%s: %q, want %s", c.name, got, c.reason)
		}
	}
	if LockedGNOT() != 0 || core.NextSequence(emitter) != next {
		t.Errorf("a refused transfer wrote: locked %d, next sequence %d", LockedGNOT(), core.NextSequence(emitter))
	}
	// The largest payload Core takes is accepted.
	if got := abort(func() {
		LockAndPublishWithPayload(cross(cur), testUser, 10, 2, testRecipient, big[:tokenbridge.MaxTransferPayload], 0)
	}); got != "" {
		t.Errorf("1,915-byte payload: %q", got)
	}
	// lockedGNOT never wraps: with nearly the int64 maximum locked, a funded
	// lock fails with amount-out-of-range.
	lockedGNOT = maxInt64 - 5
	fund(10)
	if got := abort(func() { LockAndPublish(cross(cur), testUser, 10, 2, testRecipient, 0, 0) }); got != "amount-out-of-range" {
		t.Errorf("lockedGNOT overflow: %q", got)
	}
	if LockedGNOT() != maxInt64-5 {
		t.Errorf("locked %d", LockedGNOT())
	}
}

// TestBurnAndPublish burns a wrapped asset and publishes it: above the
// balance it fails with burn-exceeds-balance and burns and publishes nothing;
// for the balance, the holder keeps nothing and the supply falls by the
// amount. An unknown origin, GNOT's included, fails with wrapped-not-found.
func TestBurnAndPublish(cur realm, t *testing.T) {
	reset()
	registerPeers(cur, t)
	emitter := vaultEmitter()
	o := origin(2, 0x03)
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	if got := abort(func() { CreateWrapped(cross(cur), meta(o, 6, "USDC", "USD Coin"), [32]byte{}) }); got != "" {
		t.Fatalf("CreateWrapped: %q", got)
	}
	symbol := WrappedSymbol(2, strings.Repeat("00", 30)+"7703")
	if got := abort(func() { Mint(cross(cur), o, testUser, 500) }); got != "" {
		t.Fatalf("Mint: %q", got)
	}
	supply, next := TotalSupply(symbol), core.NextSequence(emitter)
	if got := abort(func() { BurnAndPublish(cross(cur), o, testUser, 600, 2, testRecipient, 0, 0) }); got != "burn-exceeds-balance" {
		t.Errorf("600 of 500: %q", got)
	}
	if got := abort(func() { BurnAndPublishWithPayload(cross(cur), o, testUser, 600, 2, testRecipient, []byte{1}, 0) }); got != "burn-exceeds-balance" {
		t.Errorf("600 of 500, payload 3: %q", got)
	}
	for _, other := range []tokenbridge.Origin{origin(2, 0x98), gnotOrigin()} {
		if got := abort(func() { BurnAndPublish(cross(cur), other, testUser, 1, 2, testRecipient, 0, 0) }); got != "wrapped-not-found" {
			t.Errorf("origin %d:%x: %q", other.Chain, other.Address, got)
		}
	}
	if BalanceOf(symbol, testUser) != 500 || TotalSupply(symbol) != supply || core.NextSequence(emitter) != next {
		t.Error("a refused burn wrote")
	}
	if got := abort(func() { BurnAndPublish(cross(cur), o, testUser, 300, 2, testRecipient, 300, 0) }); got != "" {
		t.Fatalf("burn 300: %q", got)
	}
	if got := abort(func() { BurnAndPublishWithPayload(cross(cur), o, testUser, 200, 3, testRecipient, []byte{1}, 0) }); got != "" {
		t.Fatalf("burn 200 with a payload: %q", got)
	}
	if BalanceOf(symbol, testUser) != 0 || TotalSupply(symbol) != supply-500 || core.NextSequence(emitter) != next+2 {
		t.Errorf("after the burns: balance %d, supply %d, next sequence %d", BalanceOf(symbol, testUser),
			TotalSupply(symbol), core.NextSequence(emitter))
	}
	if LockedGNOT() != 0 {
		t.Errorf("a burn locked %d", LockedGNOT())
	}
}

// TestPublishGNOTMeta publishes GNOT's AssetMeta, from the configuration,
// under the vault's emitter. The payload itself is pinned by the events
// filetest.
func TestPublishGNOTMeta(cur realm, t *testing.T) {
	reset()
	emitter := vaultEmitter()
	next := core.NextSequence(emitter)
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	var seq uint64
	if got := abort(func() { seq = PublishGNOTMeta(cross(cur), 9) }); got != "" || seq != next {
		t.Fatalf("%q, sequence %d of %d", got, seq, next)
	}
	m, err := tokenbridge.ParseAssetMeta(gnotMeta())
	if err != nil || m.Token != gnotOrigin() || m.Decimals != 6 || tokenbridge.String32(m.Symbol) != "GNOT" ||
		tokenbridge.String32(m.Name) != "Gno.land" {
		t.Errorf("GNOT's AssetMeta: %v %v", m, err)
	}
}
