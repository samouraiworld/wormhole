package tokenbridge

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"crypto/bech32"
	"encoding/hex"
	"strings"
	"testing"
	"time"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/core"
)

// Named tests for the vault. The test runner runs them under its test
// configuration: Core's corpus set 3 under Wormhole chain ID 65535, on gno
// test's chain ID, dev, and the vault with logic v1. A test stands for the
// current logic by calling as its path.

const (
	testTime = 1_800_000_000
	// testSender is a realm that is not the logic.
	testSender = "gno.land/r/wormhole_test/tbsender"
	// vaultPath is this realm's path, whose address the tests fund.
	vaultPath = "gno.land/r/wormhole/tokenbridge"
)

var (
	// testUser and testOther are users, named by valid addresses.
	testUser      = chain.PackageAddress("gno.land/r/wormhole_test/user")
	testOther     = chain.PackageAddress("gno.land/r/wormhole_test/other")
	testRecipient = [32]byte{31: 0xee}
)

// reset restores the state init leaves, at the bound chain ID and the test
// time. Test functions share one store. The wrapped assets stay, since
// grc20reg keeps their registrations; tests create each asset once, under
// its own origin.
func reset() {
	logic = initialLogic
	boundChainID = gnoChainID
	pendingChainID, proposedAt = "", 0
	paused, pauseExpiry = false, 0
	pauser, freezer, unpauser = "", "", ""
	peers = avl.Tree{}
	consumed = avl.Tree{}
	redeemed = avl.Tree{}
	claims = avl.Tree{}
	staged = avl.Tree{}
	verifiedBodies = avl.Tree{}
	lockedGNOT = 0
	recordedBalance = balanceOf(vaultAddress())
	setChainID(gnoChainID)
	setTime(testTime)
}

func vaultAddress() address { return chain.PackageAddress(vaultPath) }

// abort runs fn and returns what it panics with: the reason code of a
// "tokenbridge: " panic, any other string whole (Core's codes keep their
// "core: " prefix), or "". revive catches a panic that crosses a realm
// boundary, a crossing call's; recover catches the rest.
func abort(fn func()) (reason string) {
	defer func() {
		if r := recover(); r != nil {
			reason = text(r)
		}
	}()
	return text(revive(fn))
}

func text(r any) string {
	if r == nil {
		return ""
	}
	s, ok := r.(string)
	if !ok {
		return "unexpected panic"
	}
	return strings.TrimPrefix(s, "tokenbridge: ")
}

func setTime(unix int64) {
	ctx := testing.GetContext()
	ctx.Time = time.Unix(unix, 0)
	testing.SetContext(ctx)
}

func setChainID(id string) {
	ctx := testing.GetContext()
	ctx.ChainID = id
	testing.SetContext(ctx)
}

func unhex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("bad hex: %v", err)
	}
	return b
}

func vaa(t *testing.T, name string) []byte {
	t.Helper()
	wire, ok := testGovernance[name]
	if !ok {
		t.Fatalf("no vector %s", name)
	}
	return unhex(t, wire)
}

// fund issues ugnot to the vault, as the logic's send before a lock does.
func fund(amount int64) {
	testing.IssueCoins(vaultAddress(), chain.NewCoins(chain.NewCoin("ugnot", amount)))
}

func ugnot(a address) int64 {
	return banker.NewReadonlyBanker().GetCoin(a, "ugnot")
}

// vaultEmitter is the vault's address, left-padded: gno's token-bridge
// emitter.
func vaultEmitter() [32]byte {
	return padded(addressBytes(vaultAddress()))
}

// origin is a foreign token's origin on chain, whose address ends in b.
func origin(chain uint16, b byte) tokenbridge.Origin {
	return tokenbridge.Origin{Chain: chain, Address: [32]byte{30: 0x77, 31: b}}
}

func meta(o tokenbridge.Origin, decimals uint8, symbol, name string) tokenbridge.AssetMeta {
	m := tokenbridge.AssetMeta{Token: o, Decimals: decimals}
	copy(m.Symbol[:], symbol)
	copy(m.Name[:], name)
	return m
}

// TestConfig applies init's checks to configurations, each with one
// fault, given Core's chain IDs (65535, dev) and the runtime's.
func TestConfig(t *testing.T) {
	long := strings.Repeat("x", 33)
	for _, c := range []struct {
		name        string
		chainID     uint16
		gnoChain    string
		initial     string
		symbol      string
		gnotName    string
		runtime     string
		height      int64
		coreChainID uint16
		reason      string
	}{
		{"test configuration", 65535, "dev", initialLogic, "GNOT", "Gno.land", "dev", 1, 65535, ""},
		{"chain ID 0", 0, "dev", initialLogic, "GNOT", "Gno.land", "dev", 1, 0, "invalid-configuration"},
		{"no gno chain ID", 65535, "", initialLogic, "GNOT", "Gno.land", "dev", 1, 65535, "invalid-configuration"},
		{"test chain ID off a test chain", 65535, "gnoland-1", initialLogic, "GNOT", "Gno.land", "gnoland-1", 1,
			65535, "invalid-configuration"},
		{"another network", 65535, "dev", initialLogic, "GNOT", "Gno.land", "tendermint_test", 1, 65535,
			"wrong-network"},
		{"another network at height 0", 65535, "dev", initialLogic, "GNOT", "Gno.land", "tendermint_test", 0, 65535,
			""},
		{"wrong network before Core's chain ID", 7, "dev", initialLogic, "GNOT", "Gno.land", "tendermint_test", 1,
			65535, "wrong-network"},
		{"Core's chain ID differs", 7, "dev", initialLogic, "GNOT", "Gno.land", "dev", 1, 65535,
			"invalid-configuration"},
		{"Core's gno chain ID differs", 65535, "tendermint_test", initialLogic, "GNOT", "Gno.land", "tendermint_test",
			1, 65535, "invalid-configuration"},
		{"no initial logic", 65535, "dev", "", "GNOT", "Gno.land", "dev", 1, 65535, "invalid-configuration"},
		{"a maketx run path as the first logic", 65535, "dev", "gno.land/e/" + string(testUser) + "/run", "GNOT",
			"Gno.land", "dev", 1, 65535, "invalid-configuration"},
		{"a package as the first logic", 65535, "dev", "gno.land/p/wormhole/x", "GNOT", "Gno.land", "dev", 1, 65535,
			"invalid-configuration"},
		{"a sub-realm as the first logic", 65535, "dev", initialLogic + "#sub", "GNOT", "Gno.land", "dev", 1, 65535,
			"invalid-configuration"},
		{"a bare name as the first logic", 65535, "dev", "logic", "GNOT", "Gno.land", "dev", 1, 65535,
			"invalid-configuration"},
		{"a realm with no name", 65535, "dev", "gno.land/r/", "GNOT", "Gno.land", "dev", 1, 65535,
			"invalid-configuration"},
		{"empty symbol", 65535, "dev", initialLogic, "", "Gno.land", "dev", 1, 65535, "invalid-configuration"},
		{"symbol over 32 bytes", 65535, "dev", initialLogic, long, "Gno.land", "dev", 1, 65535,
			"invalid-configuration"},
		{"zero byte in the name", 65535, "dev", initialLogic, "GNOT", "Gno\x00land", "dev", 1, 65535,
			"invalid-configuration"},
		{"name over 32 bytes", 65535, "dev", initialLogic, "GNOT", long, "dev", 1, 65535, "invalid-configuration"},
	} {
		got := checkConfig(c.chainID, c.gnoChain, c.initial, c.symbol, c.gnotName, c.coreChainID, "dev", c.runtime,
			c.height)
		if got != c.reason {
			t.Errorf("%s: %q, want %q", c.name, got, c.reason)
		}
	}
}

// TestTestConfiguration checks the configuration the test runner wrote: its
// chain IDs equal Core's, and the rest is the committed file's
// values. The state init leaves is checked on a fresh store, by
// z_init_state_filetest.gno.
func TestTestConfiguration(t *testing.T) {
	if wormholeChainID != core.ChainID() || gnoChainID != core.GnoChainID() {
		t.Errorf("test configuration %d %s, Core %d %s", wormholeChainID, gnoChainID, core.ChainID(), core.GnoChainID())
	}
	if initialLogic != "gno.land/r/wormhole/tokenbridge/logic/v1" || gnotSymbol != "GNOT" || gnotName != "Gno.land" {
		t.Errorf("committed values %s %s %s", initialLogic, gnotSymbol, gnotName)
	}
}

// TestVaultAddress checks that the tests' vaultPath names this realm, so
// that fund pays the vault.
func TestVaultAddress(cur realm, t *testing.T) {
	if cur.Address() != vaultAddress() || cur.PkgPath() != vaultPath {
		t.Errorf("realm %s %s, vaultPath %s", cur.Address(), cur.PkgPath(), vaultAddress())
	}
}

// TestDecodeAddress checks the lookup-table decode against the checksummed
// decoder, and the encoding back, and that a malformed address fails with
// caller-address-malformed, the empty one included.
func TestDecodeAddress(t *testing.T) {
	for _, path := range []string{"gno.land/r/a", testSender, vaultPath} {
		a := chain.PackageAddress(path)
		_, want, err := bech32.DecodeToBase256(string(a))
		if err != nil {
			t.Fatal(err)
		}
		got := addressBytes(a)
		if string(got[:]) != string(want) || encodeAddress(got) != a {
			t.Errorf("%s: %x", a, got)
		}
	}
	// Only the 32 data characters are read: a wrong checksum still decodes.
	a := string(testUser)
	if got := addressBytes(address(a[:34] + "qqqqqq")); got != addressBytes(testUser) {
		t.Errorf("checksum read: %x", got)
	}
	for _, bad := range []string{"", "g1", a + "q", a[:39], strings.ToUpper(a), "g2" + a[2:],
		a[:10] + "b" + a[11:], a[:10] + "\x80" + a[11:], a[:33] + "I" + a[34:]} {
		if got := abort(func() { addressBytes(address(bad)) }); got != "caller-address-malformed" {
			t.Errorf("%q: %q", bad, got)
		}
	}
}

type op struct {
	name string
	fn   func()
}

// valueOps calls each logic-only value operation once, with arguments
// that do not matter before the caller check and the gate.
func valueOps(cur realm) []op {
	o := origin(2, 0xff)
	return []op{
		{"LockAndPublish", func() { LockAndPublish(cross(cur), testUser, 1, 2, testRecipient, 0, 0) }},
		{"LockAndPublishWithPayload", func() { LockAndPublishWithPayload(cross(cur), testUser, 1, 2, testRecipient, nil, 0) }},
		{"BurnAndPublish", func() { BurnAndPublish(cross(cur), o, testUser, 1, 2, testRecipient, 0, 0) }},
		{"BurnAndPublishWithPayload", func() { BurnAndPublishWithPayload(cross(cur), o, testUser, 1, 2, testRecipient, nil, 0) }},
		{"PublishGNOTMeta", func() { PublishGNOTMeta(cross(cur), 0) }},
		{"Release", func() { Release(cross(cur), testUser, 0) }},
		{"Mint", func() { Mint(cross(cur), o, testUser, 0) }},
		{"MarkRedeemed", func() { MarkRedeemed(cross(cur), 2, testRecipient, 1) }},
		{"RecordClaim", func() { RecordClaim(cross(cur), 2, testRecipient, 2, tokenbridge.Claim{}) }},
		{"CompleteClaim", func() { CompleteClaim(cross(cur), 2, testRecipient, 3, nil, testUser) }},
		{"CancelClaim", func() { CancelClaim(cross(cur), 2, testRecipient, 4) }},
		{"CreateWrapped", func() { CreateWrapped(cross(cur), meta(o, 6, "X", "X"), [32]byte{}) }},
	}
}

// untouched fails if a refused call wrote: a write made before a panic
// survives revive in gno test.
func untouched(t *testing.T, what string) {
	t.Helper()
	if lockedGNOT != 0 || redeemed.Size() != 0 || claims.Size() != 0 || staged.Size() != 0 ||
		verifiedBodies.Size() != 0 || consumed.Size() != 0 || core.NextSequence(vaultEmitter()) != publishedBefore {
		t.Errorf("%s wrote", what)
	}
}

// publishedBefore is the vault's next Core sequence when the test began.
var publishedBefore uint64

// TestNotCurrentLogic presents every value operation from callers other than
// the current logic: a user, a maketx run script, another realm, and the
// first logic once a switch replaced it. Each fails with not-current-logic,
// before the gate, and writes nothing.
func TestNotCurrentLogic(cur realm, t *testing.T) {
	reset()
	publishedBefore = core.NextSequence(vaultEmitter())
	paused = true // the caller check comes first
	check := func(who string) {
		for _, o := range valueOps(cur) {
			if got := abort(o.fn); got != "not-current-logic" {
				t.Errorf("%s, %s: %q", who, o.name, got)
			}
		}
	}
	testing.SetRealm(testing.NewUserRealm(testUser))
	check("a user")
	testing.SetRealm(runtime.NewRealm(testUser, "gno.land/e/"+string(testUser)+"/run"))
	check("a maketx run script")
	testing.SetRealm(testing.NewCodeRealm(testSender))
	check("another realm")
	paused = false
	testing.SetRealm(testing.NewCodeRealm(testLogicV2))
	if got := abort(func() { Upgrade(cross(cur), vaa(t, "upgrade-v2")) }); got != "" {
		t.Fatalf("switch to v2: %q", got)
	}
	consumed = avl.Tree{}
	paused = true
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	check("the old logic")
	untouched(t, "a call from another caller")
	// The control: the current logic passes the caller check, so the refusals
	// above came from the callers.
	paused = false
	testing.SetRealm(testing.NewCodeRealm(testLogicV2))
	if got := abort(func() { Release(cross(cur), testUser, 0) }); got != "" {
		t.Errorf("the current logic: %q", got)
	}
}

// TestGate checks the value gate. While paused, every value operation
// but CancelClaim fails with bridge-paused; under the chain-ID freeze, every
// one fails with bridge-frozen, CancelClaim included. Running, CancelClaim
// fails with not-paused. The staging and completion entry points are gated
// too; the wrapped-token functions stay open.
func TestGate(cur realm, t *testing.T) {
	reset()
	publishedBefore = core.NextSequence(vaultEmitter())
	w := wrappedAsset0(cur, t)
	direct := []op{
		{"StageChunk", func() { StageChunk(cross(cur), 2, testRecipient[:], 1, 0, nil) }},
		{"CommitStaged", func() { CommitStaged(cross(cur), 2, testRecipient[:], 1) }},
		{"DiscardStaged", func() { DiscardStaged(cross(cur), 2, testRecipient[:], 1) }},
		{"CompletePayload", func() { CompletePayload(cross(cur), 2, testRecipient[:], 1, nil) }},
	}
	for _, state := range []string{"paused", "frozen"} {
		reset()
		want := "bridge-paused"
		if state == "paused" {
			paused, pauseExpiry = true, maxInt64
		} else {
			setChainID("forked")
			want = "bridge-frozen"
		}
		testing.SetRealm(testing.NewCodeRealm(initialLogic))
		for _, o := range valueOps(cur) {
			expected := want
			if o.name == "CancelClaim" && state == "paused" {
				expected = "claim-not-found" // it requires the pause
			}
			if got := abort(o.fn); got != expected {
				t.Errorf("%s, %s: %q", state, o.name, got)
			}
		}
		testing.SetRealm(testing.NewUserRealm(testUser))
		for _, o := range direct {
			if got := abort(o.fn); got != want {
				t.Errorf("%s, %s: %q", state, o.name, got)
			}
		}
		untouched(t, state+" value operations")
		// The wrapped-token functions stay open.
		if got := abort(func() { Transfer(cross(cur), w, testOther, 1) }); got != "" {
			t.Errorf("%s, Transfer: %q", state, got)
		}
		if got := abort(func() { Approve(cross(cur), w, testOther, 5) }); got != "" {
			t.Errorf("%s, Approve: %q", state, got)
		}
		testing.SetRealm(testing.NewUserRealm(testOther))
		if got := abort(func() { TransferFrom(cross(cur), w, testUser, testOther, 1) }); got != "" {
			t.Errorf("%s, TransferFrom: %q", state, got)
		}
	}
	reset()
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	if got := abort(func() { CancelClaim(cross(cur), 2, testRecipient, 4) }); got != "not-paused" {
		t.Errorf("running, CancelClaim: %q", got)
	}
	// A pause holds past its expiry, until UnpauseExpired lifts it.
	paused, pauseExpiry = true, testTime+60
	setTime(testTime + 61)
	if got := abort(func() { Release(cross(cur), testUser, 0) }); got != "bridge-paused" {
		t.Errorf("after the pause's expiry: %q", got)
	}
	testing.SetRealm(testing.NewUserRealm(testOther))
	if got := abort(func() { UnpauseExpired(cross(cur)) }); got != "" {
		t.Fatalf("unpause expired: %q", got)
	}
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	if got := abort(func() { Release(cross(cur), testUser, 0) }); got != "" {
		t.Errorf("after UnpauseExpired: %q", got)
	}
}

// TestReadsNeverPanic passes undecodable arguments to every read that
// decodes one: each returns zero values.
func TestReadsNeverPanic(t *testing.T) {
	for _, h := range []string{"zz", "abc", strings.Repeat("00", 31), strings.Repeat("00", 33)} {
		if IsRedeemed(2, h, 0) || GovernanceConsumed(h) || WrappedSymbol(2, h) != "" {
			t.Errorf("%q reads as something", h)
		}
		if found, _, _, _, _, _, _, _, _, _, _, _ := Claim(2, h, 0); found {
			t.Errorf("%q names a claim", h)
		}
		if ok, committer := HasVerifiedBody(2, h, 0); ok || committer != "" {
			t.Errorf("%q has a verified body", h)
		}
		if got := StagedChunks(2, h, 0, testUser); got != "" {
			t.Errorf("%q has chunks %q", h, got)
		}
	}
	for _, stager := range []address{"", "not-an-address"} {
		if got := StagedChunks(2, hex.EncodeToString(testRecipient[:]), 0, stager); got != "" {
			t.Errorf("stager %q has chunks %q", stager, got)
		}
	}
	if AssetMetaDigest("NOPE") != "" || BalanceOf("NOPE", "") != 0 {
		t.Error("an unknown symbol reads as something")
	}
}

// wrappedAsset0 creates, once, a wrapped asset that testUser holds 1,000 of,
// and returns its symbol.
func wrappedAsset0(cur realm, t *testing.T) string {
	t.Helper()
	o := origin(2, 0)
	if s := WrappedSymbol(o.Chain, hex.EncodeToString(o.Address[:])); s != "" {
		return s
	}
	testing.SetRealm(testing.NewCodeRealm(logic))
	if got := abort(func() { CreateWrapped(cross(cur), meta(o, 6, "GATE", "Gate Token"), [32]byte{}) }); got != "" {
		t.Fatalf("CreateWrapped: %q", got)
	}
	if got := abort(func() { Mint(cross(cur), o, testUser, 1000) }); got != "" {
		t.Fatalf("Mint: %q", got)
	}
	return "GATE"
}
