package tokenbridge

import (
	"chain"
	"chain/runtime"
	"encoding/hex"
	"testing"
)

// TestRegisterChain records peers from RegisterChain VAAs, which anyone may
// present, while paused or frozen too. A peer is never replaced
// (peer-registered), and each refusal records nothing and consumes nothing.
func TestRegisterChain(cur realm, t *testing.T) {
	reset()
	paused, pauseExpiry = true, maxInt64
	setChainID("forked")
	testing.SetRealm(testing.NewUserRealm(testUser))
	registerPeers(cur, t)
	var peerA, peerB [32]byte
	for i := range peerA {
		peerA[i], peerB[i] = byte(0xa0+i), byte(0xb0+i)
	}
	if Peer(2) != hex.EncodeToString(peerA[:]) || Peer(3) != hex.EncodeToString(peerB[:]) || Peer(4) != "" {
		t.Errorf("peers %s, %s, %s", Peer(2), Peer(3), Peer(4))
	}
	consumedBefore := consumed.Size()
	for _, c := range []struct{ name, reason string }{
		{"register-2", "governance-replay"},
		{"register-2-again", "peer-registered"},
		{"register-other-target", "governance-wrong-target-chain"},
		{"register-chain-zero", "register-invalid-chain"},
		{"register-chain-gno", "register-invalid-chain"},
		{"register-zero-emitter", "register-zero-emitter"},
		{"register-nft-module", "governance-wrong-module"},
		{"register-short", "governance-malformed"},
		{"register-long", "governance-malformed"},
		{"register-wrong-chain", "governance-wrong-chain"},
		{"register-wrong-emitter", "governance-wrong-emitter"},
		{"register-no-quorum", "core: no-quorum"},
		{"pausers-set", "governance-unsupported-action"},
		{"upgrade-v2", "governance-unsupported-action"},
	} {
		if got := abort(func() { RegisterChain(cross(cur), vaa(t, c.name)) }); got != c.reason {
			t.Errorf("%s: %q, want %s", c.name, got, c.reason)
		}
	}
	if consumed.Size() != consumedBefore || peers.Size() != 2 {
		t.Errorf("refusals wrote: %d consumed, %d peers", consumed.Size()-consumedBefore, peers.Size())
	}
	for _, name := range []string{"register-2", "register-3-every-chain"} {
		d := doubleKeccak(vaa(t, name)[6+66*13:])
		if !GovernanceConsumed(hex.EncodeToString(d[:])) {
			t.Errorf("%s not consumed", name)
		}
	}
}

// TestSetPauserAddresses assigns the pause roles from SetPauserAddresses
// VAAs, which anyone may present, in every state. An all-zero role, or an
// empty one, is unassigned. A change of unpauser cancels a pending
// confirmation, even a live one; keeping the unpauser keeps it.
func TestSetPauserAddresses(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(testUser))
	set := func(name string) {
		t.Helper()
		if got := abort(func() { SetPauserAddresses(cross(cur), vaa(t, name)) }); got != "" {
			t.Fatalf("%s: %q", name, got)
		}
	}
	roles := func() (string, string, string) {
		_, _, p, f, u := PauseState()
		return p, f, u
	}
	paused, pauseExpiry = true, maxInt64 // roles rotate while paused too
	set("pausers-set")
	paused, pauseExpiry = false, 0
	p, f, u := roles()
	if p != string(chain.PackageAddress(testPauser)) || f != string(chain.PackageAddress(testFreezer)) ||
		u != string(chain.PackageAddress(testUnpauser)) {
		t.Errorf("roles %s %s %s", p, f, u)
	}
	for _, c := range []struct{ name, reason string }{
		{"pausers-set", "governance-replay"},
		{"pausers-bad-length", "governance-malformed"},
		{"pausers-trailing", "governance-malformed"},
		{"pausers-every-chain", "governance-wrong-target-chain"},
		{"pausers-action-5", "governance-unsupported-action"},
		{"register-2", "governance-unsupported-action"},
	} {
		if got := abort(func() { SetPauserAddresses(cross(cur), vaa(t, c.name)) }); got != c.reason {
			t.Errorf("%s: %q, want %s", c.name, got, c.reason)
		}
	}
	// A live proposal survives a rotation that keeps the unpauser, and a
	// change of unpauser cancels it.
	setChainID("forked")
	pendingChainID, proposedAt = "forked", testTime
	set("pausers-swap")
	if pendingChainID != "forked" {
		t.Error("a rotation keeping the unpauser cancelled the proposal")
	}
	set("pausers-rotate")
	if pendingChainID != "" || proposedAt != 0 {
		t.Error("a change of unpauser kept the proposal")
	}
	if _, _, u := roles(); u != string(chain.PackageAddress(testUnpauser2)) {
		t.Errorf("unpauser %s", u)
	}
	for _, name := range []string{"pausers-unassigned", "pausers-zero"} {
		forget(t, "pausers-set")
		set("pausers-set")
		set(name)
		if p, f, u := roles(); p != "" || f != "" || u != "" {
			t.Errorf("%s: roles %s %s %s", name, p, f, u)
		}
	}
}

// forget removes a consumed VAA's digest, so that a test can apply it again.
func forget(t *testing.T, name string) {
	d := doubleKeccak(vaa(t, name)[6+66*13:])
	consumed.Remove(string(d[:]))
}

// TestUpgrade switches the logic: only to
// the code realm the VAA names, presenting it itself, never under the
// chain-ID freeze, while paused too. The other module's upgrade, another
// target chain, a VAA below quorum and a non-governance emitter are all
// refused, as is a replay.
func TestUpgrade(cur realm, t *testing.T) {
	reset()
	registerPeers(cur, t)
	lockGNOT(cur, t, 10)
	redeemed.Set("key", true)
	user := testUser
	for _, c := range []struct {
		name   string
		caller runtime.Realm
		vaa    string
		reason string
	}{
		{"a user", testing.NewUserRealm(user), "upgrade-v2", "upgrade-caller"},
		{"a maketx run script", runtime.NewRealm(user, "gno.land/e/"+string(user)+"/run"), "upgrade-v2", "upgrade-caller"},
		{"a sub-realm", runtime.NewRealm(chain.PackageAddress(testLogicV2+"#sub"), testLogicV2+"#sub"), "upgrade-v2", "upgrade-caller"},
		{"the current logic", testing.NewCodeRealm(initialLogic), "upgrade-v2", "upgrade-caller"},
		{"v3 with v2's VAA", testing.NewCodeRealm(testLogicV3), "upgrade-v2", "upgrade-wrong-realm"},
		{"every chain", testing.NewCodeRealm(testLogicV2), "upgrade-v2-every-chain", "governance-wrong-target-chain"},
		{"another chain", testing.NewCodeRealm(testLogicV2), "upgrade-v2-other-chain", "governance-wrong-target-chain"},
		{"the NFT bridge's", testing.NewCodeRealm(testLogicV2), "upgrade-v2-nft-module", "governance-wrong-module"},
		{"cut short", testing.NewCodeRealm(testLogicV2), "upgrade-v2-short", "governance-malformed"},
		{"a non-governance emitter chain", testing.NewCodeRealm(testLogicV2), "upgrade-v2-wrong-chain", "governance-wrong-chain"},
		{"a non-governance emitter", testing.NewCodeRealm(testLogicV2), "upgrade-v2-wrong-emitter", "governance-wrong-emitter"},
		{"below quorum", testing.NewCodeRealm(testLogicV2), "upgrade-v2-no-quorum", "core: no-quorum"},
		{"a RegisterChain", testing.NewCodeRealm(testLogicV2), "register-chain-zero", "governance-unsupported-action"},
	} {
		testing.SetRealm(c.caller)
		if got := abort(func() { Upgrade(cross(cur), vaa(t, c.vaa)) }); got != c.reason {
			t.Errorf("%s: %q, want %s", c.name, got, c.reason)
		}
	}
	// Under the freeze, while paused too, a switch fails with bridge-frozen,
	// after the caller check.
	paused = true
	setChainID("forked")
	testing.SetRealm(testing.NewUserRealm(user))
	if got := abort(func() { Upgrade(cross(cur), vaa(t, "upgrade-v2")) }); got != "upgrade-caller" {
		t.Errorf("a user under the freeze: %q", got)
	}
	testing.SetRealm(testing.NewCodeRealm(testLogicV2))
	// The freeze comes before the governance checks.
	for _, name := range []string{"upgrade-v2", "upgrade-v2-no-quorum", "register-2"} {
		if got := abort(func() { Upgrade(cross(cur), vaa(t, name)) }); got != "bridge-frozen" {
			t.Errorf("%s under the freeze: %q", name, got)
		}
	}
	if Logic() != initialLogic || consumed.Size() != 2 {
		t.Fatalf("refused switches wrote: logic %s, %d consumed", Logic(), consumed.Size())
	}
	// Paused, the switch is accepted, and changes nothing else.
	setChainID(gnoChainID)
	if got := abort(func() { Upgrade(cross(cur), vaa(t, "upgrade-v2")) }); got != "" {
		t.Fatalf("switch while paused: %q", got)
	}
	if Logic() != testLogicV2 || LockedGNOT() != 10 || !redeemed.Has("key") || peers.Size() != 2 || !paused {
		t.Errorf("after the switch: logic %s, locked %d", Logic(), LockedGNOT())
	}
	testing.SetRealm(testing.NewCodeRealm(testLogicV3))
	if got := abort(func() { Upgrade(cross(cur), vaa(t, "upgrade-v2")) }); got != "governance-replay" {
		t.Errorf("the consumed VAA from v3: %q", got)
	}
	testing.SetRealm(testing.NewCodeRealm(initialLogic))
	if got := abort(func() { Release(cross(cur), testUser, 0) }); got != "not-current-logic" {
		t.Errorf("v1 after the switch: %q", got)
	}
	testing.SetRealm(testing.NewCodeRealm(testLogicV3))
	if got := abort(func() { Upgrade(cross(cur), vaa(t, "upgrade-v3")) }); got != "" {
		t.Fatalf("switch to v3: %q", got)
	}
	if Logic() != testLogicV3 {
		t.Errorf("logic %s", Logic())
	}
}

// pauseRoles assigns the roles of pausers-set, as anyone may.
func pauseRoles(cur realm, t *testing.T) {
	t.Helper()
	if got := abort(func() { SetPauserAddresses(cross(cur), vaa(t, "pausers-set")) }); got != "" {
		t.Fatalf("pausers-set: %q", got)
	}
}

// TestPauseManagement checks whitepaper 0003's roles: an unassigned role fails
// with role-unassigned before any comparison, a wrong caller with not-role.
// A pause lasts 5 days and never shortens a later expiry
// (pause-not-extended); a freeze lasts until the unpauser lifts it; anyone
// may lift an expired pause.
func TestPauseManagement(cur realm, t *testing.T) {
	reset()
	for _, f := range []func(){func() { Pause(cross(cur)) }, func() { Freeze(cross(cur)) }, func() { Unpause(cross(cur)) }} {
		if got := abort(f); got != "role-unassigned" {
			t.Errorf("unassigned: %q", got)
		}
	}
	pauseRoles(cur, t)
	testing.SetRealm(testing.NewCodeRealm(testFreezer))
	for _, f := range []func(){func() { Pause(cross(cur)) }, func() { Unpause(cross(cur)) }} {
		if got := abort(f); got != "not-role" {
			t.Errorf("the freezer as another role: %q", got)
		}
	}
	notFreezer(cur, t, testing.NewCodeRealm(testPauser))
	notFreezer(cur, t, testing.NewCodeRealm(testUnpauser))
	notFreezer(cur, t, testing.NewUserRealm(testUser))
	if p, _, _, _, _ := PauseState(); p {
		t.Error("a caller other than the freezer froze the bridge")
	}
	testing.SetRealm(testing.NewCodeRealm(testUnpauser))
	if got := abort(func() { Unpause(cross(cur)) }); got != "not-paused" {
		t.Errorf("unpause, running: %q", got)
	}
	if got := abort(func() { UnpauseExpired(cross(cur)) }); got != "not-paused" {
		t.Errorf("unpause expired, running: %q", got)
	}
	testing.SetRealm(testing.NewCodeRealm(testPauser))
	if got := abort(func() { Pause(cross(cur)) }); got != "" {
		t.Fatalf("pause: %q", got)
	}
	if p, expiry, _, _, _ := PauseState(); !p || expiry != testTime+pauseDuration {
		t.Errorf("paused %v until %d", p, expiry)
	}
	if got := abort(func() { Pause(cross(cur)) }); got != "pause-not-extended" {
		t.Errorf("pause again at once: %q", got)
	}
	setTime(testTime + 1)
	if got := abort(func() { Pause(cross(cur)) }); got != "" {
		t.Errorf("renew a second later: %q", got)
	}
	setTime(testTime + pauseDuration)
	if got := abort(func() { UnpauseExpired(cross(cur)) }); got != "pause-not-expired" {
		t.Errorf("unpause before the renewed expiry: %q", got)
	}
	// Lifted after its expiry, the pause records the time it was lifted.
	setTime(testTime + 1 + pauseDuration + 5)
	testing.SetRealm(testing.NewUserRealm(testUser))
	if got := abort(func() { UnpauseExpired(cross(cur)) }); got != "" {
		t.Errorf("unpause expired: %q", got)
	}
	if p, expiry, _, _, _ := PauseState(); p || expiry != testTime+1+pauseDuration+5 {
		t.Errorf("after expiry: paused %v until %d", p, expiry)
	}
	testing.SetRealm(testing.NewCodeRealm(testFreezer))
	if got := abort(func() { Freeze(cross(cur)) }); got != "" {
		t.Fatalf("freeze: %q", got)
	}
	// A repeat leaves the freeze as it was.
	if got := abort(func() { Freeze(cross(cur)) }); got != "" {
		t.Errorf("freeze again: %q", got)
	}
	if p, expiry, _, _, _ := PauseState(); !p || expiry != maxInt64 {
		t.Errorf("after a second freeze: paused %v until %d", p, expiry)
	}
	testing.SetRealm(testing.NewCodeRealm(testPauser))
	if got := abort(func() { Pause(cross(cur)) }); got != "pause-not-extended" {
		t.Errorf("a pause shortening the freeze: %q", got)
	}
	setTime(testTime + 100*pauseDuration)
	testing.SetRealm(testing.NewUserRealm(testUser))
	if got := abort(func() { UnpauseExpired(cross(cur)) }); got != "pause-not-expired" {
		t.Errorf("the freeze never expires: %q", got)
	}
	testing.SetRealm(testing.NewCodeRealm(testUnpauser))
	if got := abort(func() { Unpause(cross(cur)) }); got != "" {
		t.Errorf("unpause the freeze: %q", got)
	}
	if p, expiry, _, _, _ := PauseState(); p || expiry != testTime+100*pauseDuration {
		t.Errorf("after unpause: paused %v until %d", p, expiry)
	}
	// Pause management runs under the chain-ID freeze too, on every network.
	setChainID("forked")
	pauseAs(cur, t, testPauser, "Pause")
	setTime(testTime + 106*pauseDuration)
	pauseAs(cur, t, "", "UnpauseExpired")
	pauseAs(cur, t, testFreezer, "Freeze")
	pauseAs(cur, t, testUnpauser, "Unpause")
}

// pauseAs makes one pause-management call as the realm at path, or as
// testUser for "".
func pauseAs(cur realm, t *testing.T, path, call string) {
	t.Helper()
	if path == "" {
		testing.SetRealm(testing.NewUserRealm(testUser))
	} else {
		testing.SetRealm(testing.NewCodeRealm(path))
	}
	var got string
	switch call {
	case "Pause":
		got = abort(func() { Pause(cross(cur)) })
	case "Freeze":
		got = abort(func() { Freeze(cross(cur)) })
	case "Unpause":
		got = abort(func() { Unpause(cross(cur)) })
	case "UnpauseExpired":
		got = abort(func() { UnpauseExpired(cross(cur)) })
	}
	if got != "" {
		t.Errorf("%s under the chain-ID freeze: %q", call, got)
	}
}

// notFreezer checks that caller cannot freeze.
func notFreezer(cur realm, t *testing.T, caller runtime.Realm) {
	t.Helper()
	testing.SetRealm(caller)
	if got := abort(func() { Freeze(cross(cur)) }); got != "not-role" {
		t.Errorf("Freeze by %s: %q", caller.Address(), got)
	}
}

// TestChainIDConfirmation runs the chain-ID confirmation on the vault:
// proposal and execution only under the freeze (not-frozen), by the unpauser
// for a proposal; execution in the 24 hours after the 24-hour delay
// (confirmation-early, confirmation-expired), while the runtime ID still
// equals the proposal (confirmation-stale); a live proposal cancelled by the
// freezer, one that is not live by anyone.
func TestChainIDConfirmation(cur realm, t *testing.T) {
	reset()
	pauseRoles(cur, t)
	testing.SetRealm(testing.NewCodeRealm(testUnpauser))
	if got := abort(func() { ProposeChainID(cross(cur)) }); got != "not-frozen" {
		t.Errorf("propose, bound: %q", got)
	}
	if got := abort(func() { ExecuteChainID(cross(cur)) }); got != "not-frozen" {
		t.Errorf("execute, bound: %q", got)
	}
	if got := abort(func() { CancelChainID(cross(cur)) }); got != "no-pending-confirmation" {
		t.Errorf("cancel, nothing pending: %q", got)
	}
	setChainID("forked")
	if got := abort(func() { ExecuteChainID(cross(cur)) }); got != "no-pending-confirmation" {
		t.Errorf("execute, nothing pending: %q", got)
	}
	testing.SetRealm(testing.NewCodeRealm(testPauser))
	if got := abort(func() { ProposeChainID(cross(cur)) }); got != "not-role" {
		t.Errorf("propose by the pauser: %q", got)
	}
	// A pause does not stop confirmation.
	paused, pauseExpiry = true, maxInt64
	testing.SetRealm(testing.NewCodeRealm(testUnpauser))
	if got := abort(func() { ProposeChainID(cross(cur)) }); got != "" {
		t.Fatalf("propose: %q", got)
	}
	if bound, pending, at := BoundChainID(); bound != "dev" || pending != "forked" || at != testTime {
		t.Errorf("proposal %s %s %d", bound, pending, at)
	}
	testing.SetRealm(testing.NewUserRealm(testUser))
	if got := abort(func() { CancelChainID(cross(cur)) }); got != "not-role" {
		t.Errorf("cancel a live proposal by anyone: %q", got)
	}
	setTime(testTime + confirmationDelay - 1)
	if got := abort(func() { ExecuteChainID(cross(cur)) }); got != "confirmation-early" {
		t.Errorf("execute early: %q", got)
	}
	setTime(testTime + confirmationDelay + confirmationWindow)
	if got := abort(func() { ExecuteChainID(cross(cur)) }); got != "confirmation-expired" {
		t.Errorf("execute late: %q", got)
	}
	// An expired proposal stays pending; another runtime ID makes it stale,
	// and anyone may cancel it then.
	setTime(testTime + confirmationDelay)
	setChainID("forked-again")
	if got := abort(func() { ExecuteChainID(cross(cur)) }); got != "confirmation-stale" {
		t.Errorf("execute, runtime moved: %q", got)
	}
	if got := abort(func() { CancelChainID(cross(cur)) }); got != "" {
		t.Errorf("cancel a stale proposal by anyone: %q", got)
	}
	setChainID("forked")
	testing.SetRealm(testing.NewCodeRealm(testUnpauser))
	if got := abort(func() { ProposeChainID(cross(cur)) }); got != "" {
		t.Fatalf("propose again: %q", got)
	}
	testing.SetRealm(testing.NewCodeRealm(testFreezer))
	setTime(testTime + 2*confirmationDelay)
	if got := abort(func() { CancelChainID(cross(cur)) }); got != "" {
		t.Errorf("the freezer cancels after the delay: %q", got)
	}
	testing.SetRealm(testing.NewCodeRealm(testUnpauser))
	if got := abort(func() { ProposeChainID(cross(cur)) }); got != "" {
		t.Fatalf("propose a third time: %q", got)
	}
	setTime(testTime + 3*confirmationDelay)
	testing.SetRealm(testing.NewUserRealm(testUser))
	if got := abort(func() { ExecuteChainID(cross(cur)) }); got != "" {
		t.Fatalf("execute: %q", got)
	}
	if bound, pending, at := BoundChainID(); bound != "forked" || pending != "" || at != 0 {
		t.Errorf("after execution: %s %s %d", bound, pending, at)
	}
	if got := abort(func() { ExecuteChainID(cross(cur)) }); got != "not-frozen" {
		t.Errorf("execute again: %q", got)
	}
}

// lapseKinds lists every state-changing vault call that TestLapse makes, in
// the order its setups need.
var lapseKinds = []string{
	"LockAndPublish", "LockAndPublishWithPayload", "BurnAndPublish", "BurnAndPublishWithPayload",
	"PublishGNOTMeta", "Release", "Mint", "MarkRedeemed", "RecordClaim", "CompleteClaim", "CreateWrapped",
	"StageChunk", "CommitStaged", "DiscardStaged", "CompletePayload", "Transfer", "Approve", "TransferFrom",
	"RegisterChain", "Upgrade", "Pause", "Unpause", "UnpauseExpired", "Freeze", "CancelClaim",
	"SetPauserAddresses",
}

// TestLapse checks that every successful state-changing vault call under a
// runtime ID other than the proposal's clears it, after its checks, while a
// read or a refused call does not. The confirmation steps,
// which handle the proposal themselves, are TestChainIDConfirmation's.
func TestLapse(cur realm, t *testing.T) {
	reset()
	pauseRoles(cur, t)
	registerPeers(cur, t)
	w := wrappedAsset0(cur, t)
	body := testBody(bodyHeaderLen+150, 9)
	for _, kind := range lapseKinds {
		lapseSetup(cur, t, kind, body)
		proposeForked(cur, t)
		_ = Render("")
		_ = IsRedeemed(2, "", 0)
		// Refused calls, after a check each of a different kind, lapse
		// nothing: a value operation's caller check, a role, the logic
		// switch's caller check, a governance payload, and an ungated
		// wrapped-token function's symbol.
		testing.SetRealm(testing.NewUserRealm(testUser))
		for _, c := range []struct {
			reason string
			fn     func()
		}{
			{"not-current-logic", func() { Release(cross(cur), testUser, 0) }},
			{"not-role", func() { Pause(cross(cur)) }},
			{"upgrade-caller", func() { Upgrade(cross(cur), vaa(t, "upgrade-v3")) }},
			{"governance-malformed", func() { SetPauserAddresses(cross(cur), vaa(t, "pausers-bad-length")) }},
			{"wrapped-not-found", func() { Transfer(cross(cur), "NOPE", testOther, 1) }},
		} {
			if got := abort(c.fn); got != c.reason {
				t.Fatalf("before %s, a refused call: %q, want %s", kind, got, c.reason)
			}
		}
		if pendingChainID != "forked" {
			t.Fatalf("before %s: a read or a refused call lapsed the proposal", kind)
		}
		if got := lapseCall(cur, t, kind, w, body); got != "" {
			t.Fatalf("%s: %q", kind, got)
		}
		if pendingChainID != "" || proposedAt != 0 {
			t.Errorf("%s did not lapse the proposal", kind)
		}
	}
	// Under the proposal's own chain ID a successful call keeps it; under a
	// third one, neither the bound ID nor the proposal's, it lapses.
	testing.SetRealm(testing.NewCodeRealm(testUnpauser))
	if paused {
		if got := abort(func() { Unpause(cross(cur)) }); got != "" {
			t.Fatalf("unpause: %q", got)
		}
	}
	setChainID("forked")
	if got := abort(func() { ProposeChainID(cross(cur)) }); got != "" {
		t.Fatalf("propose: %q", got)
	}
	// pausers-swap, the last call above, made the freezer's realm the pauser.
	testing.SetRealm(testing.NewCodeRealm(testFreezer))
	if got := abort(func() { Pause(cross(cur)) }); got != "" || pendingChainID != "forked" {
		t.Errorf("a pause under the live proposal's ID: %q, pending %q", got, pendingChainID)
	}
	setChainID("forked-again")
	setTime(blockTime() + 1)
	if got := abort(func() { Pause(cross(cur)) }); got != "" || pendingChainID != "" {
		t.Errorf("a pause under a third chain ID: %q, pending %q", got, pendingChainID)
	}
}

// proposeForked has the unpauser propose "forked", then returns to the bound
// chain ID, under which the proposal is not live.
func proposeForked(cur realm, t *testing.T) {
	t.Helper()
	setChainID("forked")
	testing.SetRealm(testing.NewCodeRealm(testUnpauser))
	if got := abort(func() { ProposeChainID(cross(cur)) }); got != "" {
		t.Fatalf("propose: %q", got)
	}
	setChainID(gnoChainID)
}

// lapseSetup prepares kind's call; whatever it does may lapse a proposal, so
// it runs before the proposal is made. testing.SetRealm takes effect in a
// named function's frame, not a closure's.
func lapseSetup(cur realm, t *testing.T, kind string, body []byte) {
	t.Helper()
	got := ""
	switch kind {
	case "LockAndPublish", "LockAndPublishWithPayload":
		fund(1)
	case "CompleteClaim":
		testing.SetRealm(testing.NewCodeRealm(logic))
		got = abort(func() { RecordClaim(cross(cur), 2, testRecipient, 3, newClaim(1, gnotOrigin(), 1, 0, testTime, body)) })
	case "StageChunk":
		payloadClaim(cur, t, 4, 0, testTime, body)
	case "CompletePayload":
		payloadClaim(cur, t, 5, 0, testTime, body)
	case "RegisterChain":
		forget(t, "register-3-every-chain")
		peers.Remove(chainKey(3))
	case "Freeze", "SetPauserAddresses":
		if paused {
			testing.SetRealm(testing.NewCodeRealm(testUnpauser))
			got = abort(func() { Unpause(cross(cur)) })
		}
	case "UnpauseExpired":
		testing.SetRealm(testing.NewCodeRealm(testPauser))
		got = abort(func() { Pause(cross(cur)) })
		setTime(blockTime() + pauseDuration)
	case "CancelClaim":
		testing.SetRealm(testing.NewCodeRealm(testUnpauser))
		got = abort(func() { Unpause(cross(cur)) })
		if got == "" {
			testing.SetRealm(testing.NewCodeRealm(logic))
			got = abort(func() {
				RecordClaim(cross(cur), 2, testRecipient, 6, newClaim(1, gnotOrigin(), 1, 0, blockTime()+100, body))
			})
		}
		if got == "" {
			testing.SetRealm(testing.NewCodeRealm(testPauser))
			got = abort(func() { Pause(cross(cur)) })
		}
	}
	if got != "" {
		t.Fatalf("setup of %s: %q", kind, got)
	}
}

// lapseCall makes kind's call, once, as its caller.
func lapseCall(cur realm, t *testing.T, kind, w string, body []byte) string {
	t.Helper()
	wo := origin(2, 0)
	testing.SetRealm(testing.NewCodeRealm(logic))
	switch kind {
	case "LockAndPublish":
		return abort(func() { LockAndPublish(cross(cur), testUser, 1, 2, testRecipient, 0, 0) })
	case "LockAndPublishWithPayload":
		return abort(func() { LockAndPublishWithPayload(cross(cur), testUser, 1, 2, testRecipient, nil, 0) })
	case "BurnAndPublish":
		return abort(func() { BurnAndPublish(cross(cur), wo, testUser, 1, 2, testRecipient, 0, 0) })
	case "BurnAndPublishWithPayload":
		return abort(func() { BurnAndPublishWithPayload(cross(cur), wo, testUser, 1, 2, testRecipient, nil, 0) })
	case "PublishGNOTMeta":
		return abort(func() { PublishGNOTMeta(cross(cur), 0) })
	case "Release":
		return abort(func() { Release(cross(cur), testUser, 0) })
	case "Mint":
		return abort(func() { Mint(cross(cur), wo, testUser, 1) })
	case "MarkRedeemed":
		return abort(func() { MarkRedeemed(cross(cur), 2, testRecipient, 1) })
	case "RecordClaim":
		return abort(func() { RecordClaim(cross(cur), 2, testRecipient, 2, newClaim(1, gnotOrigin(), 1, 0, testTime, body)) })
	case "CompleteClaim":
		return abort(func() { CompleteClaim(cross(cur), 2, testRecipient, 3, body, testUser) })
	case "CreateWrapped":
		return abort(func() { CreateWrapped(cross(cur), meta(origin(9, 1), 6, "LAPSE", "Lapse"), [32]byte{}) })
	case "CancelClaim":
		return abort(func() { CancelClaim(cross(cur), 2, testRecipient, 6) })
	}
	testing.SetRealm(testing.NewCodeRealm(testOperator))
	switch kind {
	case "StageChunk":
		return abort(func() { StageChunk(cross(cur), 2, testRecipient[:], 4, 0, body) })
	case "CommitStaged":
		return abort(func() { CommitStaged(cross(cur), 2, testRecipient[:], 4) })
	case "DiscardStaged":
		return abort(func() { DiscardStaged(cross(cur), 2, testRecipient[:], 4) })
	}
	testing.SetRealm(testing.NewCodeRealm(testRecipientRealm))
	if kind == "CompletePayload" {
		return abort(func() { CompletePayload(cross(cur), 2, testRecipient[:], 5, body) })
	}
	testing.SetRealm(testing.NewUserRealm(testUser))
	switch kind {
	case "Transfer":
		return abort(func() { Transfer(cross(cur), w, testOther, 1) })
	case "Approve":
		return abort(func() { Approve(cross(cur), w, testOther, 5) })
	case "RegisterChain":
		return abort(func() { RegisterChain(cross(cur), vaa(t, "register-3-every-chain")) })
	case "SetPauserAddresses":
		return abort(func() { SetPauserAddresses(cross(cur), vaa(t, "pausers-swap")) })
	case "UnpauseExpired":
		return abort(func() { UnpauseExpired(cross(cur)) })
	}
	testing.SetRealm(testing.NewUserRealm(testOther))
	if kind == "TransferFrom" {
		return abort(func() { TransferFrom(cross(cur), w, testUser, testOther, 1) })
	}
	testing.SetRealm(testing.NewCodeRealm(testLogicV2))
	if kind == "Upgrade" {
		return abort(func() { Upgrade(cross(cur), vaa(t, "upgrade-v2")) })
	}
	testing.SetRealm(testing.NewCodeRealm(testPauser))
	if kind == "Pause" {
		return abort(func() { Pause(cross(cur)) })
	}
	testing.SetRealm(testing.NewCodeRealm(testUnpauser))
	if kind == "Unpause" {
		return abort(func() { Unpause(cross(cur)) })
	}
	testing.SetRealm(testing.NewCodeRealm(testFreezer))
	if kind == "Freeze" {
		return abort(func() { Freeze(cross(cur)) })
	}
	return "unknown kind " + kind
}
