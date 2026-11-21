package core

import (
	"chain"
	"chain/runtime"
	"crypto/bech32"
	"encoding/hex"
	"strconv"
	"strings"
	"testing"
	"time"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/wormhole/vaa/v0"
)

// Named negative tests for the reason codes that no corpus vector
// reaches, and for the remaining edge cases. The test runner runs them
// under its test configuration: the corpus's set 3 under Wormhole chain ID
// 65535, on gno test's chain ID, dev.

// reset restores the state init leaves, except that it records Core's
// balance as it now is, as SetMessageFee would, so a test can set messageFee
// directly. Test functions share one store, its balances included.
func reset() {
	sets = avl.Tree{}
	consumed = avl.Tree{}
	sequences = avl.Tree{}
	sets.Set(setKey(initialSetIndex), &guardianSet{keys: initialKeys})
	currentIndex = initialSetIndex
	messageFee = 0
	recordedBalance = balance(coreAddress)
}

// abort runs fn and returns the reason code it panics with, or "". revive
// catches a panic that crosses a realm boundary, a crossing call's; recover
// catches the rest, a non-crossing call's.
func abort(fn func()) (reason string) {
	defer func() {
		if r := recover(); r != nil {
			reason = code(r)
		}
	}()
	return code(revive(fn))
}

func code(r any) string {
	if r == nil {
		return ""
	}
	s, ok := r.(string)
	if !ok || !strings.HasPrefix(s, "core: ") {
		return "unexpected panic"
	}
	return s[len("core: "):]
}

func setTime(unix int64) {
	ctx := testing.GetContext()
	ctx.Time = time.Unix(unix, 0)
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

// decoded returns the 20 bytes of a bech32 address, left-padded to 32,
// through the checksummed decoder.
func decoded(t *testing.T, a address) [32]byte {
	t.Helper()
	_, b, err := bech32.DecodeToBase256(string(a))
	if err != nil || len(b) != 20 {
		t.Fatalf("bad address %s", a)
	}
	var e [32]byte
	copy(e[12:], b)
	return e
}

// unchanged fails unless the state is still what reset left: set 3 current with
// its keys, no expiry and no flag, no set 4, nothing consumed and no message
// fee. A write made before a panic survives revive in gno test, so a rejection
// that wrote before its last check shows here.
func unchanged(t *testing.T, what string) {
	t.Helper()
	keys, expiration, expired, ok := GuardianSet(initialSetIndex)
	if CurrentGuardianSetIndex() != initialSetIndex || !ok || keys != initialKeys || expiration != 0 || expired {
		t.Errorf("%s changed the current set", what)
	}
	if _, _, _, ok := GuardianSet(initialSetIndex + 1); ok {
		t.Errorf("%s stored set 4", what)
	}
	if consumed.Size() != 0 {
		t.Errorf("%s consumed a digest", what)
	}
	if messageFee != 0 {
		t.Errorf("%s set the message fee", what)
	}
}

// verified parses a VAA signed by set 3 as SubmitGovernance's verification
// does, for the tests that call upgrade directly.
func verified(t *testing.T, wire string) vaa.VAA {
	t.Helper()
	v, err := vaa.Verify(unhex(t, wire), initialKeys, governanceBound)
	if err != nil {
		t.Fatal(err)
	}
	return v
}

// withIndex returns a copy of an upgrade's payload after its action byte,
// naming another index.
func withIndex(p []byte, index uint32) []byte {
	p = append([]byte(nil), p...)
	p[2], p[3], p[4], p[5] = byte(index>>24), byte(index>>16), byte(index>>8), byte(index)
	return p
}

// withTarget returns a copy of an upgrade's payload after its action byte,
// aimed at another chain.
func withTarget(p []byte, chainID uint16) []byte {
	p = append([]byte(nil), p...)
	p[0], p[1] = byte(chainID>>8), byte(chainID)
	return p
}

func TestCheckConfig(t *testing.T) {
	key := strings.Repeat("\x01", 20)
	for _, tc := range []struct {
		name          string
		chainID       uint16
		gnoChain      string
		index, replay uint32
		keys, runtime string
		height        int64
		want          string
	}{
		{"valid", 7, "gnoland-1", 3, 3, key, "gnoland-1", 5, ""},
		{"chain ID 0", 0, "gnoland-1", 3, 3, key, "gnoland-1", 5, "invalid-configuration"},
		{"no gno chain ID", 7, "", 3, 3, key, "gnoland-1", 5, "invalid-configuration"},
		{"replay index below the initial set", 7, "gnoland-1", 3, 2, key, "gnoland-1", 5, "invalid-configuration"},
		{"replay index above the initial set", 7, "gnoland-1", 3, 7, key, "gnoland-1", 5, ""},
		{"keys not packed", 7, "gnoland-1", 3, 3, key + "\x01", "gnoland-1", 5, "invalid-configuration"},
		{"test chain ID on dev", 65535, "dev", 3, 3, key, "dev", 123, ""},
		{"test chain ID on tendermint_test", 65535, "dev", 3, 3, key, "tendermint_test", 0, ""},
		{"test chain ID elsewhere", 65535, "gnoland-1", 3, 3, key, "gnoland-1", 5, "invalid-configuration"},
		{"test chain ID elsewhere at genesis", 65535, "gnoland-1", 3, 3, key, "gnoland-1", 0, "invalid-configuration"},
		{"test chain ID on another network", 65535, "dev", 3, 3, key, "gnoland-1", 5, "invalid-configuration"},
		{"wrong network", 7, "gnoland-1", 3, 3, key, "gnoland-2", 5, "wrong-network"},
		{"wrong network at height 1", 7, "gnoland-1", 3, 3, key, "gnoland-2", 1, "wrong-network"},
		{"other network at height 0", 7, "gnoland-1", 3, 3, key, "gnoland-2", 0, ""},
		{"empty set", 7, "gnoland-1", 3, 3, "", "gnoland-1", 5, "guardian-set-empty"},
		{"255 keys", 7, "gnoland-1", 3, 3, strings.Repeat(key, 255), "gnoland-1", 5, ""},
		{"256 keys", 7, "gnoland-1", 3, 3, strings.Repeat(key, 256), "gnoland-1", 5, "guardian-set-too-large"},
		{"zero key", 7, "gnoland-1", 3, 3, key + zeroKey, "gnoland-1", 5, "guardian-set-zero-key"},
		{"zero key first", 7, "gnoland-1", 3, 3, zeroKey + key, "gnoland-1", 5, "guardian-set-zero-key"},
		{"zero key alone", 7, "gnoland-1", 3, 3, zeroKey, "gnoland-1", 5, "guardian-set-zero-key"},
		{"largest index", 7, "gnoland-1", ^uint32(0), ^uint32(0), key, "gnoland-1", 5, "invalid-configuration"},
		{"one below the largest index", 7, "gnoland-1", ^uint32(0) - 1, ^uint32(0) - 1, key, "gnoland-1", 5, ""},
	} {
		got := checkConfig(tc.chainID, tc.gnoChain, tc.index, tc.replay, tc.keys, tc.runtime, tc.height)
		if got != tc.want {
			t.Errorf("%s: %q, want %q", tc.name, got, tc.want)
		}
	}
}

// TestPublicTestKeys gives init's checks a set holding one of the corpus's
// 57 public test keys, alone, first and last: invalid-configuration outside
// gno's test chains, at height 0 as at any other, and accepted on them.
// The list is generated from the corpus's three sets.
func TestPublicTestKeys(t *testing.T) {
	if len(publicTestKeys) != 57*20 {
		t.Fatalf("%d bytes of public test keys, want 57 keys", len(publicTestKeys))
	}
	other := strings.Repeat("\x01", 20)
	for i := 0; i < len(publicTestKeys); i += 20 {
		k := publicTestKeys[i : i+20]
		for _, keys := range []string{k, k + other, other + k} {
			for _, height := range []int64{0, 5} {
				if got := checkConfig(7, "gnoland-1", 3, 3, keys, "gnoland-1", height); got != "invalid-configuration" {
					t.Errorf("test key %d in a %d-key set on gnoland-1 at height %d: %q", i/20, len(keys)/20, height, got)
				}
			}
			for _, chain := range []string{"dev", "tendermint_test"} {
				if got := checkConfig(7, chain, 3, 3, keys, chain, 5); got != "" {
					t.Errorf("test key %d in a %d-key set on %s: %q", i/20, len(keys)/20, chain, got)
				}
			}
		}
	}
	if got := checkConfig(7, "gnoland-1", 3, 3, other, "gnoland-1", 5); got != "" {
		t.Errorf("a key outside the test sets: %q", got)
	}
}

// TestGovernanceArithmeticOverflow submits a valid upgrade when its expiry
// would pass the uint32 maximum, including at a block time beyond uint32
// (2^33 seconds; a time past 2262 does not fit the test context).
func TestGovernanceArithmeticOverflow(cur realm, t *testing.T) {
	raw := unhex(t, testUpgrade)
	for _, now := range []int64{1<<32 - setExpiry, 1 << 33} {
		reset()
		setTime(now)
		if got := abort(func() { SubmitGovernance(cross(cur), raw) }); got != "governance-arithmetic-overflow" {
			t.Errorf("at %d: %q", now, got)
		}
		unchanged(t, "the overflow at "+strconv.FormatInt(now, 10))
	}
	// One second earlier the expiry still fits.
	reset()
	setTime(1<<32 - setExpiry - 1)
	if got := abort(func() { SubmitGovernance(cross(cur), raw) }); got != "" {
		t.Errorf("last time that fits: %q", got)
	}
	// At the largest index the next one would wrap. The header's set index
	// is not signed, so the same VAA can name a set stored there.
	reset()
	setTime(testTime)
	sets.Set(setKey(^uint32(0)), &guardianSet{keys: initialKeys})
	currentIndex = ^uint32(0)
	renamed := unhex(t, testUpgrade)
	renamed[1], renamed[2], renamed[3], renamed[4] = 0xff, 0xff, 0xff, 0xff
	if got := abort(func() { SubmitGovernance(cross(cur), renamed) }); got != "governance-arithmetic-overflow" {
		t.Errorf("largest index: %q", got)
	}
	// Nothing written: no expiry for the current set, no set at the wrapped
	// index 0, nothing consumed.
	_, expiration, expired, _ := GuardianSet(^uint32(0))
	_, _, _, wrapped := GuardianSet(0)
	if CurrentGuardianSetIndex() != ^uint32(0) || expiration != 0 || expired || wrapped || consumed.Size() != 0 {
		t.Error("largest index: the rejection changed state")
	}
}

// TestExpiryPastUint32 upgrades at the last time that fits, so the replaced
// set expires at the uint32 maximum, and verifies with it on both sides of
// that second: block time is compared at full width.
func TestExpiryPastUint32(cur realm, t *testing.T) {
	reset()
	setTime(1<<32 - 1 - setExpiry)
	if got := abort(func() { SubmitGovernance(cross(cur), unhex(t, testUpgrade)) }); got != "" {
		t.Fatalf("upgrade: %q", got)
	}
	if _, expiration, _, _ := GuardianSet(3); expiration != ^uint32(0) {
		t.Fatalf("set 3 expires at %d", expiration)
	}
	for now, want := range map[int64]string{1<<32 - 1: "", 1 << 32: "guardian-set-expired", 1 << 33: "guardian-set-expired"} {
		setTime(now)
		if got := abort(func() { VerifyVAA(unhex(t, testVerify)) }); got != want {
			t.Errorf("set 3 at %d: %q, want %q", now, got, want)
		}
	}
}

// TestGovernanceMalformed submits signed governance VAAs whose payloads end
// after the module, after the action and after the target chain.
func TestGovernanceMalformed(cur realm, t *testing.T) {
	reset()
	setTime(testTime)
	for i, wire := range testShortGovernance {
		if got := abort(func() { SubmitGovernance(cross(cur), unhex(t, wire)) }); got != "governance-malformed" {
			t.Errorf("payload %d: %q", i, got)
		}
	}
	unchanged(t, "a malformed payload")
}

// TestGovernanceAliasReplay accepts an upgrade, then submits its body signed
// by the new set with a malleated signature: the same digest is a replay.
func TestGovernanceAliasReplay(cur realm, t *testing.T) {
	reset()
	setTime(testTime)
	if got := abort(func() { SubmitGovernance(cross(cur), unhex(t, testUpgrade)) }); got != "" {
		t.Fatalf("upgrade: %q", got)
	}
	var digest [32]byte
	copy(digest[:], unhex(t, testUpgradeDigest))
	if !GovernanceConsumed(digest) || CurrentGuardianSetIndex() != 4 {
		t.Fatal("the upgrade was not applied")
	}
	for _, alias := range []string{testUpgradeBySet4, testUpgradeBySet4HighS} {
		if got := abort(func() { SubmitGovernance(cross(cur), unhex(t, alias)) }); got != "governance-replay" {
			t.Errorf("same body: %q", got)
		}
	}
	// The original, signed by set 3, is no longer current.
	if got := abort(func() { SubmitGovernance(cross(cur), unhex(t, testUpgrade)) }); got != "governance-not-current-set" {
		t.Errorf("original: %q", got)
	}
	_, expiration, expired, _ := GuardianSet(4)
	_, _, _, five := GuardianSet(5)
	if CurrentGuardianSetIndex() != 4 || consumed.Size() != 1 || expiration != 0 || expired || five {
		t.Error("a rejected replay changed state")
	}
}

// TestGovernanceConsumed reads the upgrade's digest before it is submitted,
// after a rejected submission and after the accepted one.
func TestGovernanceConsumed(cur realm, t *testing.T) {
	reset()
	var digest [32]byte
	copy(digest[:], unhex(t, testUpgradeDigest))
	if GovernanceConsumed(digest) {
		t.Error("consumed before any submission")
	}
	setTime(1<<32 - setExpiry)
	if got := abort(func() { SubmitGovernance(cross(cur), unhex(t, testUpgrade)) }); got != "governance-arithmetic-overflow" {
		t.Fatalf("upgrade: %q", got)
	}
	if GovernanceConsumed(digest) {
		t.Error("consumed after a rejected submission")
	}
	unchanged(t, "the rejected submission")
	setTime(testTime)
	if got := abort(func() { SubmitGovernance(cross(cur), unhex(t, testUpgrade)) }); got != "" {
		t.Fatalf("upgrade: %q", got)
	}
	if !GovernanceConsumed(digest) {
		t.Error("not consumed after the accepted submission")
	}
}

// TestVerifyConsumesNothing verifies an upgrade VAA, which writes nothing,
// so the upgrade can still be submitted.
func TestVerifyConsumesNothing(cur realm, t *testing.T) {
	reset()
	setTime(testTime)
	var digest [32]byte
	copy(digest[:], unhex(t, testUpgradeDigest))
	if v := VerifyVAA(unhex(t, testUpgrade)); v.Digest != digest {
		t.Fatalf("VerifyVAA gives digest %x", v.Digest)
	}
	unchanged(t, "VerifyVAA")
	if got := abort(func() { SubmitGovernance(cross(cur), unhex(t, testUpgrade)) }); got != "" {
		t.Errorf("upgrade after VerifyVAA: %q", got)
	}
}

// TestNegativeBlockTime upgrades at block time -1, which gno.land never
// gives: it counts as 0, so the replaced set gets setExpiry seconds from 0,
// where wrapping -1 into a uint32 would give it one second less.
func TestNegativeBlockTime(cur realm, t *testing.T) {
	reset()
	setTime(-1)
	if got := abort(func() { SubmitGovernance(cross(cur), unhex(t, testUpgrade)) }); got != "" {
		t.Fatalf("upgrade: %q", got)
	}
	if _, expiration, _, _ := GuardianSet(3); expiration != setExpiry {
		t.Errorf("set 3 expires at %d, want %d", expiration, setExpiry)
	}
}

// TestGovernanceFaults submits governance VAAs that break two of
// SubmitGovernance's rules, or one rule in a high byte only: Core reports
// the reason the reference model does, and writes nothing.
func TestGovernanceFaults(cur realm, t *testing.T) {
	reset()
	setTime(testTime)
	for _, f := range testGovernanceFaults {
		if got := abort(func() { SubmitGovernance(cross(cur), unhex(t, f.wire)) }); got != f.reason {
			t.Errorf("%s: %q, want %q", f.name, got, f.reason)
		}
	}
	unchanged(t, "a governance fault")
}

// governanceVAA builds a 13-signature VAA from set 3 whose signatures are
// zero, with a governance body and a payload of n bytes. Any check after the
// payload bound refuses it with invalid-signature.
func governanceVAA(n int) []byte {
	raw := []byte{1, 0, 0, 0, 3, 13}
	for i := 0; i < 13; i++ {
		raw = append(raw, byte(i))
		raw = append(raw, make([]byte, 65)...)
	}
	body := make([]byte, 51)
	body[9] = 1 // emitter chain 1
	copy(body[10:42], governanceEmitter)
	return append(append(raw, body...), make([]byte, n)...)
}

// TestPayloadBounds pins Core's payload bounds to their
// values: 5,140 bytes for governance and 500,000 for VerifyVAA. A payload one
// byte over is malformed before any signature is checked.
func TestPayloadBounds(cur realm, t *testing.T) {
	reset()
	setTime(testTime)
	for n, want := range map[int]string{5_140: "invalid-signature", 5_141: "malformed"} {
		if got := abort(func() { SubmitGovernance(cross(cur), governanceVAA(n)) }); got != want {
			t.Errorf("governance, %d bytes: %q", n, got)
		}
	}
	for n, want := range map[int]string{5_141: "invalid-signature", 500_000: "invalid-signature", 500_001: "malformed"} {
		if got := abort(func() { VerifyVAA(governanceVAA(n)) }); got != want {
			t.Errorf("VerifyVAA, %d bytes: %q", n, got)
		}
	}
	unchanged(t, "a VAA refused for its length or signatures")
}

// TestReplayPath: while the current index is below replayUntilIndex, an
// accepted upgrade flags the replaced set expired at once. At block time 0
// the flag alone refuses it, since its expiration time is 0 too.
func TestReplayPath(t *testing.T) {
	for _, now := range []int64{testTime, 0} {
		for _, replay := range []uint32{initialSetIndex, initialSetIndex + 1} {
			reset()
			setTime(now)
			v, err := vaa.Verify(unhex(t, testUpgrade), initialKeys, governanceBound)
			if err != nil {
				t.Fatal(err)
			}
			upgrade(v.Digest, v.Payload[33:], now, wormholeChainID, replay)
			_, expiration, expired, _ := GuardianSet(3)
			got := abort(func() { VerifyVAA(unhex(t, testVerify)) })
			if replay == initialSetIndex && (expired || int64(expiration) != now+setExpiry || got != "") {
				t.Errorf("fresh path at %d: expired %v, expiration %d, verify %q", now, expired, expiration, got)
			}
			if replay > initialSetIndex && (!expired || expiration != 0 || got != "guardian-set-expired") {
				t.Errorf("replay path at %d: expired %v, expiration %d, verify %q", now, expired, expiration, got)
			}
		}
	}
}

// TestReplayPathOverflow submits the upgrade on the replay path when the
// replaced set's expiry would pass the uint32 maximum. That path stores no
// expiry, but every check is the fresh path's.
func TestReplayPathOverflow(t *testing.T) {
	reset()
	v := verified(t, testUpgrade)
	now := int64(1<<32 - setExpiry)
	if got := abort(func() { upgrade(v.Digest, v.Payload[33:], now, wormholeChainID, initialSetIndex+1) }); got != "governance-arithmetic-overflow" {
		t.Errorf("replay path at %d: %q", now, got)
	}
	unchanged(t, "the overflow on the replay path")
}

// TestUpgradeTargetChain runs upgrade on Wormhole chain 0x0102, whose two
// bytes differ, unlike the test configuration's 65535: the target chain is
// read big-endian and compared with the configured chain.
func TestUpgradeTargetChain(t *testing.T) {
	v := verified(t, testUpgrade)
	for target, want := range map[uint16]string{
		0x0102: "",
		0:      "",
		0x0201: "governance-wrong-target-chain",
		0xffff: "governance-wrong-target-chain",
	} {
		reset()
		if got := abort(func() {
			upgrade(v.Digest, withTarget(v.Payload[33:], target), testTime, 0x0102, initialSetIndex)
		}); got != want {
			t.Errorf("target %#04x: %q, want %q", target, got, want)
		}
		if want != "" {
			unchanged(t, "a refused target chain")
		}
	}
}

// TestUpgradeIndexNotNext names the index below the current one, the
// current one and the one after next: only current + 1 is accepted.
func TestUpgradeIndexNotNext(t *testing.T) {
	v := verified(t, testUpgrade)
	for _, index := range []uint32{initialSetIndex - 1, initialSetIndex, initialSetIndex + 2} {
		reset()
		if got := abort(func() {
			upgrade(v.Digest, withIndex(v.Payload[33:], index), testTime, wormholeChainID, initialSetIndex)
		}); got != "guardian-set-index-not-next" {
			t.Errorf("index %d: %q", index, got)
		}
		unchanged(t, "index "+strconv.FormatUint(uint64(index), 10))
	}
}

// TestLastIndexUpgrade applies the last upgrade the index allows, from
// 2^32-2 to 2^32-1, and the replaced set gets its 24 hours.
func TestLastIndexUpgrade(t *testing.T) {
	reset()
	v := verified(t, testUpgrade)
	sets.Set(setKey(^uint32(0)-1), &guardianSet{keys: initialKeys})
	currentIndex = ^uint32(0) - 1
	if got := abort(func() {
		upgrade(v.Digest, withIndex(v.Payload[33:], ^uint32(0)), testTime, wormholeChainID, initialSetIndex)
	}); got != "" {
		t.Fatalf("upgrade: %q", got)
	}
	_, expiration, _, _ := GuardianSet(^uint32(0) - 1)
	if CurrentGuardianSetIndex() != ^uint32(0) || int64(expiration) != testTime+setExpiry {
		t.Errorf("current set %d, set 2^32-2 expires at %d", CurrentGuardianSetIndex(), expiration)
	}
}

// TestUpgradeShortKeyList gives upgrade bodies with fewer key bytes than
// their count declares: one key short, and cut inside a key.
func TestUpgradeShortKeyList(t *testing.T) {
	v := verified(t, testUpgrade)
	p := v.Payload[33:]
	for _, short := range []int{20, 7} {
		reset()
		if got := abort(func() {
			upgrade(v.Digest, p[:len(p)-short], testTime, wormholeChainID, initialSetIndex)
		}); got != "governance-malformed" {
			t.Errorf("%d bytes short: %q", short, got)
		}
		unchanged(t, "a short key list")
	}
}

// TestUpgradeCheckOrder breaks two of upgrade's rules at once. The model's
// order fixes the reason: the target chain before the body's length, the
// length before the keys, the keys before an overflow or the index, and an
// overflow before the index.
func TestUpgradeCheckOrder(t *testing.T) {
	v := verified(t, testUpgrade)
	p := v.Payload[33:]
	zero := append([]byte(nil), p...)
	copy(zero[7:27], zeroKey)
	for _, tc := range []struct {
		name string
		p    []byte
		now  int64
		want string
	}{
		{"wrong target, one key short", withTarget(p[:len(p)-20], 7), testTime, "governance-wrong-target-chain"},
		{"zero key, one key short", zero[:len(zero)-20], testTime, "governance-malformed"},
		{"zero key, index after next", withIndex(zero, initialSetIndex+2), testTime, "guardian-set-zero-key"},
		{"zero key, expiry past uint32", zero, 1<<32 - setExpiry, "guardian-set-zero-key"},
		{"expiry past uint32, index after next", withIndex(p, initialSetIndex+2), 1<<32 - setExpiry, "governance-arithmetic-overflow"},
	} {
		reset()
		if got := abort(func() { upgrade(v.Digest, tc.p, tc.now, wormholeChainID, initialSetIndex) }); got != tc.want {
			t.Errorf("%s: %q, want %q", tc.name, got, tc.want)
		}
		unchanged(t, tc.name)
	}
}

// TestPublishPayloadTooLarge: a payload over 2,048 bytes is refused before
// the emitter's sequence is used, so its next message still gets 0.
func TestPublishPayloadTooLarge(cur realm, t *testing.T) {
	reset()
	user := chain.PackageAddress("gno.land/r/wormhole_test/user")
	testing.SetRealm(testing.NewUserRealm(user))
	if got := abort(func() { PublishMessage(cross(cur), 0, make([]byte, 2_049), 1) }); got != "payload-too-large" {
		t.Errorf("2,049 bytes: %q", got)
	}
	if next := NextSequence(decoded(t, user)); next != 0 {
		t.Errorf("after the refusal the next sequence is %d", next)
	}
	var seq uint64
	if got := abort(func() { seq = PublishMessage(cross(cur), 0, make([]byte, 2_048), 1) }); got != "" || seq != 0 {
		t.Errorf("2,048 bytes: %q, sequence %d", got, seq)
	}
}

// TestPublishMalformedAddress publishes as a user whose address holds a
// character outside bech32: refused, and no sequence is used. gno test
// cannot make the caller of a vm/qeval query, whose address is empty:
// testing.SetRealm ignores a realm with no address. TestUserEmitter gives
// emitterOf that address instead.
func TestPublishMalformedAddress(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm("g1bg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"))
	if got := abort(func() { PublishMessage(cross(cur), 0, nil, 1) }); got != "publisher-address-malformed" {
		t.Errorf("%q", got)
	}
	if sequences.Size() != 0 {
		t.Error("a malformed address used a sequence")
	}
}

// TestPublishEphemeral publishes from the realm of a maketx run script,
// gno.land/e/<user>/run: refused before the payload is even measured, and
// with no sequence used.
func TestPublishEphemeral(cur realm, t *testing.T) {
	reset()
	user := chain.PackageAddress("gno.land/r/wormhole_test/user")
	testing.SetRealm(runtime.NewRealm(user, "gno.land/e/"+string(user)+"/run"))
	for _, n := range []int{0, 2_049} {
		if got := abort(func() { PublishMessage(cross(cur), 0, make([]byte, n), 1) }); got != "publisher-ephemeral" {
			t.Errorf("%d bytes: %q", n, got)
		}
	}
	if sequences.Size() != 0 {
		t.Error("an ephemeral publisher used a sequence")
	}
}

func TestPublishSequenceExhausted(cur realm, t *testing.T) {
	reset()
	path := "gno.land/r/wormhole_test/full"
	testing.SetRealm(testing.NewCodeRealm(path))
	emitter := decoded(t, chain.PackageAddress(path))
	sequences.Set(string(emitter[:]), &seqCell{next: ^uint64(0) - 1})
	if seq := PublishMessage(cross(cur), 0, nil, 1); seq != ^uint64(0)-1 {
		t.Errorf("last sequence: %d", seq)
	}
	if got := abort(func() { PublishMessage(cross(cur), 0, nil, 1) }); got != "sequence-exhausted" {
		t.Errorf("after the last sequence: %q", got)
	}
	if NextSequence(emitter) != ^uint64(0) {
		t.Errorf("next sequence %d", NextSequence(emitter))
	}
}

// TestPerEmitterSequences alternates two realms: each counts its own
// messages, under the emitter its address gives.
func TestPerEmitterSequences(cur realm, t *testing.T) {
	reset()
	paths := []string{"gno.land/r/wormhole_test/a", "gno.land/r/wormhole_test/b"}
	for _, path := range paths {
		if next := NextSequence(decoded(t, chain.PackageAddress(path))); next != 0 {
			t.Errorf("%s: next sequence %d before any message", path, next)
		}
	}
	for round := uint64(0); round < 3; round++ {
		for _, path := range paths {
			testing.SetRealm(testing.NewCodeRealm(path))
			if seq := PublishMessage(cross(cur), 0, nil, 1); seq != round {
				t.Errorf("%s round %d: sequence %d", path, round, seq)
			}
		}
	}
	for _, path := range paths {
		if next := NextSequence(decoded(t, chain.PackageAddress(path))); next != 3 {
			t.Errorf("%s: next sequence %d", path, next)
		}
	}
}

// TestUserEmitter checks the lookup-table decode against the checksummed
// decoder, and that a malformed address is refused. Only the 32 data
// characters are read: the checksum is not checked.
func TestUserEmitter(t *testing.T) {
	for _, path := range []string{"gno.land/r/a", "gno.land/r/wormhole_test/user", "gno.land/r/x/y/z"} {
		a := chain.PackageAddress(path)
		if emitterOf("", a) != decoded(t, a) {
			t.Errorf("%s: emitter differs from its bech32 decoding", a)
		}
	}
	good := address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	if emitterOf("", "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqfb") != decoded(t, good) {
		t.Error("a bad checksum character changed the emitter")
	}
	for _, bad := range []address{
		"", // a vm/qeval query's caller: it runs with no origin caller
		"g1",
		"g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf",     // 39 characters
		"g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5q",   // 41 characters
		"x1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5",    // another prefix
		"gqjg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5",    // g, then not 1
		"g1bg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5",    // b is not a bech32 character
		"g1Jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5",    // nor is an upper-case one
		"g1jg8mtutu9khhfwc4nxmuhcpftf0pajdofvsqf5",    // o, as the last data character
		"g1\xffg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5", // nor is a byte above 127
	} {
		if got := abort(func() { emitterOf("", bad) }); got != "publisher-address-malformed" {
			t.Errorf("%s: %q", bad, got)
		}
	}
}

// TestUserEmitterEveryCharacter decodes an address whose 32 data characters
// are the whole bech32 alphabet, in value order, so every lookup-table
// entry is used once.
func TestUserEmitterEveryCharacter(t *testing.T) {
	// 20 bytes whose 32 five-bit groups are 0, 1, ..., 31.
	var b [20]byte
	var acc uint32
	bits, j := 0, 0
	for v := uint32(0); v < 32; v++ {
		acc = (acc<<5 | v) & 0xffff
		bits += 5
		if bits >= 8 {
			bits -= 8
			b[j] = byte(acc >> uint(bits))
			j++
		}
	}
	s, err := bech32.EncodeFromBase256("g", b[:])
	if err != nil {
		t.Fatal(err)
	}
	if s[2:34] != "qpzry9x8gf2tvdw0s3jn54khce6mua7l" {
		t.Fatalf("data part %s is not the alphabet", s[2:34])
	}
	if a := address(s); emitterOf("", a) != decoded(t, a) {
		t.Errorf("%s: emitter differs from its bech32 decoding", a)
	}
}

func TestRenderNeverEchoesPath(t *testing.T) {
	reset()
	want := "# Wormhole Core\n\n- Wormhole chain ID: 65535\n- Gno chain ID: dev\n- Current guardian set: 3, 19 guardians\n" +
		"- Message fee: 0 ugnot\n"
	for _, path := range []string{"", "<script>alert(1)</script>", "[x](javascript:y)"} {
		if got := Render(path); got != want {
			t.Errorf("Render(%q) = %q", path, got)
		}
	}
}
