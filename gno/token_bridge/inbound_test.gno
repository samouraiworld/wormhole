package tokenbridge

import (
	"encoding/hex"
	"strings"
	"testing"

	"gno.land/p/nt/grc20/v0"
	"gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/nt/grc20reg/v0"
)

// badChecksum is testUser with its six checksum characters replaced: the
// lookup-table decode reads it, but neither the bank nor grc20 pays it.
func badChecksum() address {
	return address(string(testUser)[:34] + "qqqqqq")
}

// testBody is a stand-in VAA body: the vault checks only its double keccak
// and length.
func testBody(n int, seed byte) []byte {
	b := make([]byte, n)
	for i := range b {
		b[i] = byte(i) ^ seed
	}
	return b
}

// newClaim is a claim for testUser of amount and fee in asset, released at
// release, for body.
func newClaim(id uint8, asset tokenbridge.Origin, amount, fee, release int64, body []byte) tokenbridge.Claim {
	return tokenbridge.Claim{Digest: doubleKeccak(body), PayloadID: id, Recipient: testUser, Asset: asset,
		Amount: amount, Fee: fee, BodyLen: len(body), ReleaseTime: release}
}

// lockGNOT locks amount as the current logic, after registering chain 2.
func lockGNOT(cur realm, t *testing.T, amount int64) {
	t.Helper()
	if !peers.Has(chainKey(2)) {
		registerPeers(cur, t)
	}
	testing.SetRealm(testing.NewCodeRealm(logic))
	fund(amount)
	if got := abort(func() { LockAndPublish(cross(cur), testUser, amount, 2, testRecipient, 0, 0) }); got != "" {
		t.Fatalf("lock %d: %q", amount, got)
	}
}

// TestRelease pays GNOT out of escrow: never a negative amount
// (amount-out-of-range) or more than is locked (locked-insufficient), and
// never to an address no bank pays. A zero amount sends nothing;
// z_events_claims_filetest.gno pays a zero GNOT claim from a vault never
// funded, which gno's test banker would refuse to send from.
func TestRelease(cur realm, t *testing.T) {
	reset()
	lockGNOT(cur, t, 100)
	before := ugnot(testOther)
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	if got := abort(func() { Release(cross(cur), testOther, -1) }); got != "amount-out-of-range" {
		t.Errorf("negative: %q", got)
	}
	if got := abort(func() { Release(cross(cur), testOther, 101) }); got != "locked-insufficient" {
		t.Errorf("above the escrow: %q", got)
	}
	for _, to := range []address{"not-an-address", badChecksum()} {
		if got := abort(func() { Release(cross(cur), to, 1) }); got != "caller-address-malformed" {
			t.Errorf("to %q, which no bank pays: %q", to, got)
		}
	}
	if LockedGNOT() != 100 || ugnot(testOther) != before {
		t.Error("a refused release wrote")
	}
	if got := abort(func() { Release(cross(cur), testOther, 60) }); got != "" {
		t.Fatalf("release 60: %q", got)
	}
	if got := abort(func() { Release(cross(cur), testOther, 0) }); got != "" {
		t.Fatalf("release 0: %q", got)
	}
	if LockedGNOT() != 40 || ugnot(testOther) != before+60 || recordedBalance != ugnot(vaultAddress()) {
		t.Errorf("locked %d, paid %d, recorded %d of %d", LockedGNOT(), ugnot(testOther)-before, recordedBalance,
			ugnot(vaultAddress()))
	}
}

// TestMint mints a wrapped asset: an unknown origin fails with
// wrapped-not-found, a mint past the int64 maximum with supply-overflow, any
// other ledger refusal with wrapped-ledger-error, and a zero amount mints
// nothing.
func TestMint(cur realm, t *testing.T) {
	reset()
	o := origin(5, 0x01)
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	if got := abort(func() { CreateWrapped(cross(cur), meta(o, 8, "MINT", "Mint Token"), [32]byte{}) }); got != "" {
		t.Fatalf("CreateWrapped: %q", got)
	}
	if got := abort(func() { Mint(cross(cur), origin(5, 0x02), testUser, 1) }); got != "wrapped-not-found" {
		t.Errorf("unknown origin: %q", got)
	}
	if got := abort(func() { Mint(cross(cur), o, testUser, maxInt64) }); got != "" {
		t.Fatalf("mint the maximum: %q", got)
	}
	if got := abort(func() { Mint(cross(cur), o, testOther, 1) }); got != "supply-overflow" {
		t.Errorf("past the maximum: %q", got)
	}
	if got := abort(func() { Mint(cross(cur), o, "not-an-address", 0) }); got != "" {
		t.Errorf("zero to anyone: %q", got)
	}
	for _, c := range []struct {
		to     address
		amount int64
	}{{"not-an-address", 1}, {testOther, -1}} {
		if got := abort(func() { Mint(cross(cur), o, c.to, c.amount) }); got != "wrapped-ledger-error" {
			t.Errorf("mint %d to %q: %q", c.amount, c.to, got)
		}
	}
	if TotalSupply("MINT") != maxInt64 || BalanceOf("MINT", testOther) != 0 {
		t.Errorf("supply %d", TotalSupply("MINT"))
	}
}

// TestRedeemedAndClaims records replay keys: each at most once, by
// MarkRedeemed or RecordClaim (transfer-redeemed). A recorded claim keeps the
// logic's fields, is open, and is delayed only if its release time is later
// than the block time.
func TestRedeemedAndClaims(cur realm, t *testing.T) {
	reset()
	emitter := testRecipient
	emitterHex := hex.EncodeToString(emitter[:])
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	if got := abort(func() { MarkRedeemed(cross(cur), 2, emitter, 1) }); got != "" {
		t.Fatalf("MarkRedeemed: %q", got)
	}
	body := testBody(184, 1)
	c := newClaim(1, gnotOrigin(), 10, 1, testTime, body)
	for _, f := range []func(){
		func() { MarkRedeemed(cross(cur), 2, emitter, 1) },
		func() { RecordClaim(cross(cur), 2, emitter, 1, c) },
	} {
		if got := abort(f); got != "transfer-redeemed" {
			t.Errorf("a redeemed key again: %q", got)
		}
	}
	if !IsRedeemed(2, emitterHex, 1) || IsRedeemed(2, emitterHex, 2) || IsRedeemed(3, emitterHex, 1) {
		t.Error("IsRedeemed")
	}
	if found, _, _, _, _, _, _, _, _, _, _, _ := Claim(2, emitterHex, 1); found {
		t.Error("MarkRedeemed recorded a claim")
	}
	if got := abort(func() { RecordClaim(cross(cur), 2, emitter, 2, c) }); got != "" {
		t.Fatalf("RecordClaim: %q", got)
	}
	if got := abort(func() { RecordClaim(cross(cur), 2, emitter, 2, c) }); got != "transfer-redeemed" {
		t.Errorf("a claim twice: %q", got)
	}
	later := newClaim(3, origin(2, 9), 7, 0, testTime+1, testBody(300, 2))
	if got := abort(func() { RecordClaim(cross(cur), 2, emitter, 3, later) }); got != "" {
		t.Fatalf("RecordClaim, delayed: %q", got)
	}
	found, id, recipient, chain, asset, amount, fee, n, digest, release, delayed, state := Claim(2, emitterHex, 2)
	if !found || id != 1 || recipient != string(testUser) || chain != int(wormholeChainID) ||
		asset != hex.EncodeToString(c.Asset.Address[:]) || amount != 10 || fee != 1 || n != 184 ||
		digest != hex.EncodeToString(c.Digest[:]) || release != testTime || delayed || state != "open" {
		t.Errorf("claim 2: %v %d %s %d %s %d %d %d %s %d %v %s", found, id, recipient, chain, asset, amount, fee, n,
			digest, release, delayed, state)
	}
	if found, _, _, _, _, _, _, _, _, release, delayed, _ := Claim(2, emitterHex, 3); !found || !delayed ||
		release != testTime+1 {
		t.Errorf("claim 3: delayed %v, release %d", delayed, release)
	}
	if !IsRedeemed(2, emitterHex, 2) || !IsRedeemed(2, emitterHex, 3) {
		t.Error("a claim's key is not redeemed")
	}
}

// TestCompleteClaim completes a released payload-1 claim once, with its own
// body, under the relayer-fee rule, after the payment's checks.
func TestCompleteClaim(cur realm, t *testing.T) {
	reset()
	lockGNOT(cur, t, 100)
	e := testRecipient
	body := testBody(184, 3)
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	record := func(seq uint64, c tokenbridge.Claim) {
		if got := abort(func() { RecordClaim(cross(cur), 2, e, seq, c) }); got != "" {
			t.Fatalf("RecordClaim %d: %q", seq, got)
		}
	}
	record(1, newClaim(1, gnotOrigin(), 30, 5, testTime, body))
	record(2, newClaim(3, gnotOrigin(), 30, 0, testTime, body))
	record(3, newClaim(1, gnotOrigin(), 30, 0, testTime+10, body))
	record(4, newClaim(1, gnotOrigin(), 10, 11, testTime, body))
	record(5, newClaim(1, gnotOrigin(), 101, 0, testTime, body))
	record(6, newClaim(1, origin(9, 9), 1, 0, testTime, body))
	record(7, newClaim(1, gnotOrigin(), -1, 0, testTime, body))
	record(8, newClaim(1, gnotOrigin(), 30, -1, testTime, body))
	bad := newClaim(1, gnotOrigin(), 30, 0, testTime, body)
	bad.Recipient = "not-an-address"
	record(9, bad)
	record(10, newClaim(1, gnotOrigin(), 30, 1, testTime, body))
	sum := newClaim(1, gnotOrigin(), 30, 0, testTime, body)
	sum.Recipient = badChecksum()
	record(11, sum)
	record(12, newClaim(1, gnotOrigin(), 30, 1, testTime, body))
	for _, c := range []struct {
		name     string
		seq      uint64
		body     []byte
		redeemer address
		reason   string
	}{
		{"no claim", 99, body, testOther, "claim-not-found"},
		{"payload 3", 2, body, testOther, "claim-wrong-type"},
		{"before its release", 3, body, testOther, "claim-not-released"},
		{"another body", 1, testBody(184, 4), testOther, "claim-body-mismatch"},
		{"a fee above the amount, for a relayer", 4, body, testOther, "fee-exceeds-amount"},
		{"above the escrow", 5, body, testOther, "locked-insufficient"},
		{"an asset with no wrapper", 6, body, testOther, "wrapped-not-found"},
		{"a negative amount", 7, body, testOther, "amount-out-of-range"},
		{"a negative fee, for a relayer", 8, body, testOther, "amount-out-of-range"},
		{"a recipient no bank pays", 9, body, testOther, "caller-address-malformed"},
		{"a relayer no bank pays", 10, body, "not-an-address", "caller-address-malformed"},
		{"a recipient whose checksum is wrong", 11, body, testOther, "caller-address-malformed"},
		{"a relayer whose checksum is wrong", 12, body, badChecksum(), "caller-address-malformed"},
	} {
		if got := abort(func() { CompleteClaim(cross(cur), 2, e, c.seq, c.body, c.redeemer) }); got != c.reason {
			t.Errorf("%s: %q, want %s", c.name, got, c.reason)
		}
	}
	if LockedGNOT() != 100 {
		t.Errorf("refused completions released %d", 100-LockedGNOT())
	}
	stillOpen(t, 2, 1, 12)
	user, other := ugnot(testUser), ugnot(testOther)
	if got := abort(func() { CompleteClaim(cross(cur), 2, e, 1, body, testOther) }); got != "" {
		t.Fatalf("complete: %q", got)
	}
	if ugnot(testUser) != user+25 || ugnot(testOther) != other+5 || LockedGNOT() != 70 {
		t.Errorf("paid %d and %d, locked %d", ugnot(testUser)-user, ugnot(testOther)-other, LockedGNOT())
	}
	// The payment moved the recorded balance with it, so a lock after it
	// still needs exactly its own coins.
	if recordedBalance != ugnot(vaultAddress()) {
		t.Errorf("recorded %d of %d", recordedBalance, ugnot(vaultAddress()))
	}
	fund(3)
	if got := abort(func() { LockAndPublish(cross(cur), testUser, 3, 2, testRecipient, 0, 0) }); got != "" {
		t.Errorf("a lock after a claim's payment: %q", got)
	}
	if got := abort(func() { CompleteClaim(cross(cur), 2, e, 1, body, testOther) }); got != "claim-completed" {
		t.Errorf("twice: %q", got)
	}
	// The recipient redeeming pays no fee, even one above the amount.
	setTime(testTime + 10)
	if got := abort(func() { CompleteClaim(cross(cur), 2, e, 4, body, testUser) }); got != "" {
		t.Fatalf("complete by the recipient: %q", got)
	}
	if ugnot(testUser) != user+35 || LockedGNOT() != 63 {
		t.Errorf("the recipient got %d, locked %d", ugnot(testUser)-user, LockedGNOT())
	}
}

// TestCompleteWrappedClaim mints a wrapped claim, split under the
// relayer-fee rule, and refuses one its supply cannot take (supply-overflow).
func TestCompleteWrappedClaim(cur realm, t *testing.T) {
	reset()
	o := origin(6, 1)
	body := testBody(184, 5)
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	if got := abort(func() { CreateWrapped(cross(cur), meta(o, 6, "CLM", "Claim Token"), [32]byte{}) }); got != "" {
		t.Fatalf("CreateWrapped: %q", got)
	}
	for seq, amount := range []int64{100, maxInt64, -1} {
		if got := abort(func() {
			RecordClaim(cross(cur), 6, testRecipient, uint64(seq), newClaim(1, o, amount, 7, testTime, body))
		}); got != "" {
			t.Fatalf("RecordClaim: %q", got)
		}
	}
	if got := abort(func() { CompleteClaim(cross(cur), 6, testRecipient, 0, body, testOther) }); got != "" {
		t.Fatalf("complete: %q", got)
	}
	if BalanceOf("CLM", testUser) != 93 || BalanceOf("CLM", testOther) != 7 || TotalSupply("CLM") != 100 {
		t.Errorf("minted %d and %d", BalanceOf("CLM", testUser), BalanceOf("CLM", testOther))
	}
	if got := abort(func() { CompleteClaim(cross(cur), 6, testRecipient, 1, body, testOther) }); got != "supply-overflow" {
		t.Errorf("past the supply's maximum: %q", got)
	}
	// A negative amount, which only a faulty logic records, is refused before
	// the claim is marked completed, with no fee to refuse it first.
	if got := abort(func() { CompleteClaim(cross(cur), 6, testRecipient, 2, body, testUser) }); got != "amount-out-of-range" {
		t.Errorf("a negative wrapped claim: %q", got)
	}
	stillOpen(t, 6, 2, 2)
	// Refused before any write: the claim stays open, and nothing is minted.
	stillOpen(t, 6, 1, 1)
	if TotalSupply("CLM") != 100 {
		t.Errorf("supply %d", TotalSupply("CLM"))
	}
}

// stillOpen fails unless the claims of emitter chain e, from sequence
// first to last under testRecipient, are all still open: a refusal that
// wrote before its last check shows here, since revive keeps the write.
func stillOpen(t *testing.T, e uint16, first, last uint64) {
	t.Helper()
	for seq := first; seq <= last; seq++ {
		if _, _, _, _, _, _, _, _, _, _, _, state := Claim(e, hex.EncodeToString(testRecipient[:]), seq); state != "open" {
			t.Errorf("claim %d:%d is %s after a refused completion", e, seq, state)
		}
	}
}

// TestCancelClaim cancels a delayed claim: only while paused
// (not-paused), never under the chain-ID freeze (bridge-frozen), and only a
// delayed one (claim-not-delayed). Nothing is paid, the key stays redeemed,
// the amount stays locked, and a later completion fails with
// claim-cancelled.
func TestCancelClaim(cur realm, t *testing.T) {
	reset()
	lockGNOT(cur, t, 50)
	e := testRecipient
	body := testBody(184, 6)
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	for seq, release := range []int64{testTime + 86400, testTime} {
		if got := abort(func() { RecordClaim(cross(cur), 2, e, uint64(seq), newClaim(1, gnotOrigin(), 50, 0, release, body)) }); got != "" {
			t.Fatalf("RecordClaim: %q", got)
		}
	}
	if got := abort(func() { CancelClaim(cross(cur), 2, e, 0) }); got != "not-paused" {
		t.Errorf("running: %q", got)
	}
	paused, pauseExpiry = true, testTime+pauseDuration
	setChainID("forked")
	if got := abort(func() { CancelClaim(cross(cur), 2, e, 0) }); got != "bridge-frozen" {
		t.Errorf("paused and frozen: %q", got)
	}
	setChainID(gnoChainID)
	for _, c := range []struct {
		seq    uint64
		reason string
	}{{9, "claim-not-found"}, {1, "claim-not-delayed"}} {
		if got := abort(func() { CancelClaim(cross(cur), 2, e, c.seq) }); got != c.reason {
			t.Errorf("claim %d: %q", c.seq, got)
		}
	}
	if got := abort(func() { CancelClaim(cross(cur), 2, e, 0) }); got != "" {
		t.Fatalf("cancel: %q", got)
	}
	if got := abort(func() { CancelClaim(cross(cur), 2, e, 0) }); got != "claim-cancelled" {
		t.Errorf("cancel twice: %q", got)
	}
	paused = false
	setTime(testTime + 86400)
	if got := abort(func() { CompleteClaim(cross(cur), 2, e, 0, body, testUser) }); got != "claim-cancelled" {
		t.Errorf("complete a cancelled claim: %q", got)
	}
	if _, _, _, _, _, _, _, _, _, _, _, state := Claim(2, hex.EncodeToString(e[:]), 0); state != "cancelled" ||
		!IsRedeemed(2, hex.EncodeToString(e[:]), 0) || LockedGNOT() != 50 {
		t.Errorf("state %s, locked %d", state, LockedGNOT())
	}
	// A delayed claim that was completed cannot be cancelled.
	if got := abort(func() { RecordClaim(cross(cur), 2, e, 5, newClaim(1, gnotOrigin(), 50, 0, testTime+86401, body)) }); got != "" {
		t.Fatalf("RecordClaim: %q", got)
	}
	setTime(testTime + 86401)
	if got := abort(func() { CompleteClaim(cross(cur), 2, e, 5, body, testUser) }); got != "" {
		t.Fatalf("complete: %q", got)
	}
	paused = true
	if got := abort(func() { CancelClaim(cross(cur), 2, e, 5) }); got != "claim-completed" {
		t.Errorf("cancel a completed claim: %q", got)
	}
}

// TestCreateWrapped creates each origin's wrapper once (wrapped-exists), never
// for an origin on gno's chain (asset-meta-native), with decimals min(d, 8)
// and the naming rules' name and symbol, and registers it in grc20reg under the vault's
// path and its symbol.
func TestCreateWrapped(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	for _, o := range []tokenbridge.Origin{gnotOrigin(), origin(wormholeChainID, 1)} {
		if got := abort(func() { CreateWrapped(cross(cur), meta(o, 6, "FAKE", "Fake"), [32]byte{}) }); got != "asset-meta-native" {
			t.Errorf("gno origin %x: %q", o.Address, got)
		}
	}
	o := origin(7, 1)
	if got := abort(func() { CreateWrapped(cross(cur), meta(o, 18, "WRP", "Wrapped"), [32]byte{1}) }); got != "" {
		t.Fatalf("CreateWrapped: %q", got)
	}
	if got := abort(func() { CreateWrapped(cross(cur), meta(o, 6, "OTHER", "Other"), [32]byte{2}) }); got != "wrapped-exists" {
		t.Errorf("twice: %q", got)
	}
	// Also through a new logic.
	testing.SetRealm(testing.NewCodeRealm(testLogicV2))
	if got := abort(func() { Upgrade(cross(cur), vaa(t, "upgrade-v2")) }); got != "" {
		t.Fatalf("switch: %q", got)
	}
	if got := abort(func() { CreateWrapped(cross(cur), meta(o, 6, "OTHER", "Other"), [32]byte{2}) }); got != "wrapped-exists" {
		t.Errorf("twice, after a switch: %q", got)
	}
	tok := grc20reg.Get(vaultPath + ".WRP")
	if tok == nil || tok.GetName() != "Wrapped (Wormhole)" || tok.GetDecimals() != 8 || tok != wrappedBySymbol("WRP").token {
		t.Errorf("registered token %v", tok)
	}
	if c, a, ok := Origin("WRP"); !ok || c != 7 || a != hex.EncodeToString(o.Address[:]) {
		t.Errorf("Origin(WRP): %d %s %v", c, a, ok)
	}
	if d := AssetMetaDigest("WRP"); d != "01"+strings.Repeat("00", 31) {
		t.Errorf("AssetMetaDigest(WRP) %s", d)
	}
	// A symbol grc20 refuses, or one in use, falls back to the first unused
	// WH<n>; a name grc20 refuses, to Wormhole <chain>:<address>.
	used := 0
	for originBySymbol.Has(tokenbridge.FallbackSymbol(used + 1)) {
		used++
	}
	for i, m := range []tokenbridge.AssetMeta{
		meta(origin(7, 2), 6, "U|SD", "Pipe"),
		meta(origin(7, 3), 6, "WRP", "Bad\x01Name"),
	} {
		if got := abort(func() { CreateWrapped(cross(cur), m, [32]byte{}) }); got != "" {
			t.Fatalf("CreateWrapped %d: %q", i, got)
		}
	}
	want := []string{tokenbridge.FallbackSymbol(used + 1), tokenbridge.FallbackSymbol(used + 2)}
	for i, b := range []byte{2, 3} {
		if s := WrappedSymbol(7, strings.Repeat("00", 30)+"770"+string('0'+b)); s != want[i] {
			t.Errorf("origin %d: symbol %q, want %s", b, s, want[i])
		}
	}
	if name := wrappedBySymbol(want[1]).token.GetName(); name != "Wormhole 7:"+strings.Repeat("00", 18)+"7703" {
		t.Errorf("fallback name %q", name)
	}
}

// TestGrc20Boundaries passes the naming helpers' boundary outputs through
// grc20.NewToken, which must accept them: a 64-byte name, U+0080, invalid
// UTF-8, an 11-character symbol and WH999999999. A later pin that tightens
// grc20 then fails here, before any wrapper becomes impossible to create.
func TestGrc20Boundaries(cur realm, t *testing.T) {
	for i, c := range []struct{ name, symbol string }{
		{strings.Repeat("n", 64), "ABCDEFGHIJK"},
		{"\u0080", tokenbridge.FallbackSymbol(999999999)},
		{"\xff\xfe", "a-b_c9"},
		{tokenbridge.WrappedName(meta(origin(65535, 0xff), 0, "", "\x01")), tokenbridge.FallbackSymbol(1)},
	} {
		if !tokenbridge.ValidName(c.name) || !tokenbridge.ValidSymbol(c.symbol) {
			t.Fatalf("%d: the package refuses %q %q", i, c.name, c.symbol)
		}
		var id = tokenIDs
		if got := abort(func() { grc20.NewToken(c.name, c.symbol, 8, id.Next(), cur) }); got != "" {
			t.Errorf("%d: grc20 refuses %q %q: %q", i, c.name, c.symbol, got)
		}
	}
}
