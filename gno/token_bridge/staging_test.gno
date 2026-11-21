package tokenbridge

import (
	"chain"
	"encoding/hex"
	"testing"
)

const (
	testRecipientRealm = "gno.land/r/wormhole_test/tbrecipient"
	testOperator       = "gno.land/r/wormhole_test/operator"
	testGriefer        = "gno.land/r/wormhole_test/griefer"
)

// payloadClaim records a payload-3 GNOT claim of amount for the recipient
// realm, for body, as the current logic.
func payloadClaim(cur realm, t *testing.T, seq uint64, amount int64, release int64, body []byte) {
	t.Helper()
	c := newClaim(3, gnotOrigin(), amount, 0, release, body)
	c.Recipient = chain.PackageAddress(testRecipientRealm)
	testing.SetRealm(testing.NewCodeRealm(logic))
	if got := abort(func() { RecordClaim(cross(cur), 2, testRecipient, seq, c) }); got != "" {
		t.Fatalf("RecordClaim %d: %q", seq, got)
	}
}

// stage writes every chunk of body as the realm at path.
func stage(cur realm, t *testing.T, path string, seq uint64, body []byte) {
	t.Helper()
	testing.SetRealm(testing.NewCodeRealm(path))
	for i := 0; i*chunkSize < len(body); i++ {
		end := (i + 1) * chunkSize
		if end > len(body) {
			end = len(body)
		}
		if got := abort(func() { StageChunk(cross(cur), 2, testRecipient[:], seq, i, body[i*chunkSize:end]) }); got != "" {
			t.Fatalf("stage chunk %d: %q", i, got)
		}
	}
}

// TestStagedPayload completes a payload-3 claim whose body is at the inbound
// bound, 51 + 500,000 bytes, in parts. Its operator stages the eight chunks and
// commits; the recipient realm completes with an empty body, receives the
// amount and the payload, body[51:], and nobody else can complete it. Another
// stager's commit afterwards fails with body-already-verified, and the
// committer frees the body once completed.
func TestStagedPayload(cur realm, t *testing.T) {
	reset()
	lockGNOT(cur, t, 300)
	body := testBody(bodyHeaderLen+500_000, 7)
	payloadClaim(cur, t, 1, 300, testTime, body)
	e := hex.EncodeToString(testRecipient[:])
	operator := chain.PackageAddress(testOperator)
	// A griefer stages garbage in its own buffer, which spoils nothing.
	testing.SetRealm(testing.NewCodeRealm(testGriefer))
	if got := abort(func() { StageChunk(cross(cur), 2, testRecipient[:], 1, 7, make([]byte, len(body)-7*chunkSize)) }); got != "" {
		t.Fatalf("the griefer's chunk: %q", got)
	}
	if got := abort(func() { CommitStaged(cross(cur), 2, testRecipient[:], 1) }); got != "stage-incomplete" {
		t.Errorf("the griefer's incomplete commit: %q", got)
	}
	// A retry overwrites a chunk: chunk 0 first with wrong bytes.
	testing.SetRealm(testing.NewCodeRealm(testOperator))
	if got := abort(func() { StageChunk(cross(cur), 2, testRecipient[:], 1, 0, make([]byte, chunkSize)) }); got != "" {
		t.Fatalf("the operator's wrong chunk 0: %q", got)
	}
	stage(cur, t, testOperator, 1, body)
	if got := StagedChunks(2, e, 1, operator); got != "0,1,2,3,4,5,6,7" {
		t.Errorf("staged %q", got)
	}
	// Each stager frees only its own buffer: the griefer's discard leaves the
	// operator's chunks.
	testing.SetRealm(testing.NewCodeRealm(testGriefer))
	if got := abort(func() { DiscardStaged(cross(cur), 2, testRecipient[:], 1) }); got != "" {
		t.Errorf("the griefer discards: %q", got)
	}
	if got := StagedChunks(2, e, 1, operator); got != "0,1,2,3,4,5,6,7" {
		t.Errorf("the griefer's discard left the operator %q", got)
	}
	testing.SetRealm(testing.NewCodeRealm(testGriefer))
	if got := abort(func() { StageChunk(cross(cur), 2, testRecipient[:], 1, 7, make([]byte, len(body)-7*chunkSize)) }); got != "" {
		t.Fatalf("the griefer stages again: %q", got)
	}
	if got := StagedChunks(2, e, 1, chain.PackageAddress(testGriefer)); got != "7" {
		t.Errorf("the griefer staged %q", got)
	}
	testing.SetRealm(testing.NewCodeRealm(testOperator))
	for _, c := range []struct {
		name  string
		index int
		size  int
	}{
		{"a short chunk", 0, chunkSize - 1},
		{"a long last chunk", 7, len(body) - 7*chunkSize + 1},
		{"index 8", 8, 1},
		{"index -1", -1, chunkSize},
	} {
		if got := abort(func() { StageChunk(cross(cur), 2, testRecipient[:], 1, c.index, make([]byte, c.size)) }); got != "stage-bad-chunk" {
			t.Errorf("%s: %q", c.name, got)
		}
	}
	if got := abort(func() { CommitStaged(cross(cur), 2, testRecipient[:], 1) }); got != "" {
		t.Fatalf("commit: %q", got)
	}
	if ok, committer := HasVerifiedBody(2, e, 1); !ok || committer != string(operator) || StagedChunks(2, e, 1, operator) != "" {
		t.Errorf("verified %v by %s, staged %q", ok, committer, StagedChunks(2, e, 1, operator))
	}
	if got := StagedChunks(2, e, 1, chain.PackageAddress(testGriefer)); got != "7" {
		t.Errorf("the operator's commit left the griefer %q", got)
	}
	// While the claim is open, the committer's discard keeps its body.
	if got := abort(func() { DiscardStaged(cross(cur), 2, testRecipient[:], 1) }); got != "" {
		t.Errorf("discard, open: %q", got)
	}
	if ok, _ := HasVerifiedBody(2, e, 1); !ok {
		t.Error("a discard freed an open claim's verified body")
	}
	if got := StagedChunks(2, e, 1, chain.PackageAddress(testGriefer)); got != "7" {
		t.Errorf("the operator's discard left the griefer %q", got)
	}
	testing.SetRealm(testing.NewCodeRealm(testGriefer))
	for _, f := range []func(){
		func() { CommitStaged(cross(cur), 2, testRecipient[:], 1) },
		func() { StageChunk(cross(cur), 2, testRecipient[:], 1, 0, body[:chunkSize]) },
	} {
		if got := abort(f); got != "body-already-verified" {
			t.Errorf("after the commit: %q", got)
		}
	}
	// Only the recipient completes.
	testing.SetRealm(testing.NewCodeRealm(testOperator))
	if got := abort(func() { CompletePayload(cross(cur), 2, testRecipient[:], 1, nil) }); got != "not-recipient" {
		t.Errorf("the operator completes: %q", got)
	}
	recipient := chain.PackageAddress(testRecipientRealm)
	before := ugnot(recipient)
	testing.SetRealm(testing.NewCodeRealm(testRecipientRealm))
	var msg string
	if got := abort(func() { msg = CompletePayload(cross(cur), 2, testRecipient[:], 1, nil) }); got != "" {
		t.Fatalf("complete: %q", got)
	}
	if msg != string(body[bodyHeaderLen:]) || ugnot(recipient) != before+300 || LockedGNOT() != 0 {
		t.Errorf("payload of %d bytes, paid %d, locked %d", len(msg), ugnot(recipient)-before, LockedGNOT())
	}
	if recordedBalance != ugnot(vaultAddress()) {
		t.Errorf("recorded %d of %d", recordedBalance, ugnot(vaultAddress()))
	}
	if got := abort(func() { CompletePayload(cross(cur), 2, testRecipient[:], 1, nil) }); got != "claim-completed" {
		t.Errorf("twice: %q", got)
	}
	// The griefer's buffer and the operator's body are freed by their own.
	if ok, _ := HasVerifiedBody(2, e, 1); !ok {
		t.Error("completion freed the verified body")
	}
	testing.SetRealm(testing.NewCodeRealm(testGriefer))
	if got := abort(func() { DiscardStaged(cross(cur), 2, testRecipient[:], 1) }); got != "" {
		t.Errorf("the griefer discards: %q", got)
	}
	if ok, _ := HasVerifiedBody(2, e, 1); !ok || StagedChunks(2, e, 1, chain.PackageAddress(testGriefer)) != "" {
		t.Error("the griefer's discard freed the operator's body, or kept its own chunk")
	}
	testing.SetRealm(testing.NewCodeRealm(testOperator))
	if got := abort(func() { DiscardStaged(cross(cur), 2, testRecipient[:], 1) }); got != "" {
		t.Errorf("the committer discards: %q", got)
	}
	if ok, _ := HasVerifiedBody(2, e, 1); ok || staged.Size() != 0 || verifiedBodies.Size() != 0 {
		t.Error("the committer's discard left storage behind")
	}
}

// TestCompletePayloadChecks refuses completions in CompletePayload's order:
// the claim (claim-not-found, claim-wrong-type, claim-not-released), the
// recipient (not-recipient), then the body (claim-body-mismatch, or
// stage-incomplete with no verified body) and the escrow
// (locked-insufficient). A body passed whole completes in one call, and
// claims recorded before and after a logic switch both complete.
func TestCompletePayloadChecks(cur realm, t *testing.T) {
	reset()
	registerPeers(cur, t)
	lockGNOT(cur, t, 20)
	body := testBody(bodyHeaderLen+200, 8)
	changed := append([]byte(nil), body...)
	changed[100] ^= 1
	payloadClaim(cur, t, 1, 10, testTime, body)
	payloadClaim(cur, t, 2, 10, testTime+60, body)
	payloadClaim(cur, t, 3, 21, testTime, body)
	payloadClaim(cur, t, 4, 1, testTime, body[:bodyHeaderLen-1])
	testing.SetRealm(testing.NewCodeRealm(logic))
	if got := abort(func() { RecordClaim(cross(cur), 2, testRecipient, 5, newClaim(1, gnotOrigin(), 1, 0, testTime, body)) }); got != "" {
		t.Fatalf("RecordClaim: %q", got)
	}
	testing.SetRealm(testing.NewCodeRealm(testRecipientRealm))
	for _, c := range []struct {
		name   string
		seq    uint64
		body   []byte
		reason string
	}{
		{"no claim", 9, body, "claim-not-found"},
		{"payload 1", 5, body, "claim-wrong-type"},
		{"before its release", 2, body, "claim-not-released"},
		{"a changed body", 1, changed, "claim-body-mismatch"},
		{"no verified body", 1, nil, "stage-incomplete"},
		{"above the escrow", 3, body, "locked-insufficient"},
		{"a body shorter than its header", 4, body[:bodyHeaderLen-1], "claim-body-mismatch"},
	} {
		if got := abort(func() { CompletePayload(cross(cur), 2, testRecipient[:], c.seq, c.body) }); got != c.reason {
			t.Errorf("%s: %q, want %s", c.name, got, c.reason)
		}
	}
	testing.SetRealm(testing.NewCodeRealm(testOperator))
	if got := abort(func() { CompletePayload(cross(cur), 2, testRecipient[:], 9, body) }); got != "claim-not-found" {
		t.Errorf("no claim, another caller: %q", got)
	}
	if got := abort(func() { CompletePayload(cross(cur), 2, testRecipient[:], 1, changed) }); got != "not-recipient" {
		t.Errorf("a changed body from another caller: %q", got)
	}
	for _, f := range []func(){
		func() { StageChunk(cross(cur), 2, testRecipient[:], 5, 0, body) },
		func() { CommitStaged(cross(cur), 2, testRecipient[:], 5) },
	} {
		if got := abort(f); got != "claim-wrong-type" {
			t.Errorf("staging payload 1: %q", got)
		}
	}
	// An emitter that is not 32 bytes names no transfer, whatever its first
	// 32 bytes are.
	long := append(append([]byte(nil), testRecipient[:]...), 0)
	for _, f := range []func(){
		func() { StageChunk(cross(cur), 2, testRecipient[:], 9, 0, body) },
		func() { CommitStaged(cross(cur), 2, testRecipient[:], 9) },
		func() { DiscardStaged(cross(cur), 2, testRecipient[:], 9) },
		func() { StageChunk(cross(cur), 2, testRecipient[:31], 1, 0, body) },
		func() { StageChunk(cross(cur), 2, long, 1, 0, body) },
		func() { CommitStaged(cross(cur), 2, long, 1) },
		func() { DiscardStaged(cross(cur), 2, long, 1) },
		func() { CompletePayload(cross(cur), 2, long, 1, body) },
	} {
		if got := abort(f); got != "claim-not-found" {
			t.Errorf("staging no claim: %q", got)
		}
	}
	// A claim whose body length no verified VAA has, as only a faulty
	// logic could record, has no chunk to stage, and nothing to commit.
	for i, n := range []int{maxBodyLen + 1, maxInt64 / 2, 0, -1} {
		c := newClaim(3, gnotOrigin(), 1, 0, testTime, body)
		c.BodyLen = n
		testing.SetRealm(testing.NewCodeRealm(logic))
		if got := abort(func() { RecordClaim(cross(cur), 3, testRecipient, uint64(i), c) }); got != "" {
			t.Fatalf("RecordClaim: %q", got)
		}
		testing.SetRealm(testing.NewCodeRealm(testOperator))
		if got := abort(func() { StageChunk(cross(cur), 3, testRecipient[:], uint64(i), 0, body) }); got != "stage-bad-chunk" {
			t.Errorf("body length %d, stage: %q", n, got)
		}
		if got := abort(func() { CommitStaged(cross(cur), 3, testRecipient[:], uint64(i)) }); got != "claim-body-mismatch" {
			t.Errorf("body length %d, commit: %q", n, got)
		}
	}
	// A wrong commit is refused and keeps the buffer.
	stage(cur, t, testOperator, 1, changed)
	if got := abort(func() { CommitStaged(cross(cur), 2, testRecipient[:], 1) }); got != "claim-body-mismatch" {
		t.Errorf("commit a changed body: %q", got)
	}
	if StagedChunks(2, hex.EncodeToString(testRecipient[:]), 1, chain.PackageAddress(testOperator)) != "0" {
		t.Error("a refused commit freed the buffer")
	}
	// Switch to v2, record a claim there, and complete both claims whole.
	testing.SetRealm(testing.NewCodeRealm(testLogicV2))
	if got := abort(func() { Upgrade(cross(cur), vaa(t, "upgrade-v2")) }); got != "" {
		t.Fatalf("switch: %q", got)
	}
	payloadClaim(cur, t, 6, 10, testTime, body)
	testing.SetRealm(testing.NewCodeRealm(testRecipientRealm))
	for _, seq := range []uint64{1, 6} {
		var msg string
		if got := abort(func() { msg = CompletePayload(cross(cur), 2, testRecipient[:], seq, body) }); got != "" || msg != string(body[bodyHeaderLen:]) {
			t.Errorf("claim %d: %q", seq, got)
		}
	}
	// A completed claim takes no more staging.
	testing.SetRealm(testing.NewCodeRealm(testOperator))
	for _, f := range []func(){
		func() { StageChunk(cross(cur), 2, testRecipient[:], 1, 0, body) },
		func() { CommitStaged(cross(cur), 2, testRecipient[:], 1) },
	} {
		if got := abort(f); got != "claim-completed" {
			t.Errorf("staging a completed claim: %q", got)
		}
	}
	if LockedGNOT() != 0 {
		t.Errorf("locked %d", LockedGNOT())
	}
}

// TestCompleteWrappedPayload completes a payload-3 claim for a wrapped asset
// the recipient receives the payload and the amount, minted, and
// the GNOT escrow is untouched. A claim the supply cannot take fails with
// supply-overflow and stays open.
func TestCompleteWrappedPayload(cur realm, t *testing.T) {
	reset()
	lockGNOT(cur, t, 5)
	o := origin(8, 1)
	body := testBody(bodyHeaderLen+200, 10)
	recipient := chain.PackageAddress(testRecipientRealm)
	testing.SetRealm(testing.NewCodeRealm(logic))
	if got := abort(func() { CreateWrapped(cross(cur), meta(o, 6, "PAY3", "Payload Three"), [32]byte{}) }); got != "" {
		t.Fatalf("CreateWrapped: %q", got)
	}
	for seq, amount := range []int64{70, maxInt64, -1} {
		c := newClaim(3, o, amount, 0, testTime, body)
		c.Recipient = recipient
		if got := abort(func() { RecordClaim(cross(cur), 8, testRecipient, uint64(seq), c) }); got != "" {
			t.Fatalf("RecordClaim: %q", got)
		}
	}
	vault := ugnot(vaultAddress())
	testing.SetRealm(testing.NewCodeRealm(testRecipientRealm))
	var msg string
	if got := abort(func() { msg = CompletePayload(cross(cur), 8, testRecipient[:], 0, body) }); got != "" {
		t.Fatalf("complete: %q", got)
	}
	if msg != string(body[bodyHeaderLen:]) || BalanceOf("PAY3", recipient) != 70 || TotalSupply("PAY3") != 70 {
		t.Errorf("payload of %d bytes, balance %d, supply %d", len(msg), BalanceOf("PAY3", recipient), TotalSupply("PAY3"))
	}
	if LockedGNOT() != 5 || ugnot(vaultAddress()) != vault {
		t.Errorf("a wrapped completion moved GNOT: locked %d, balance %d of %d", LockedGNOT(), ugnot(vaultAddress()), vault)
	}
	if got := abort(func() { CompletePayload(cross(cur), 8, testRecipient[:], 1, body) }); got != "supply-overflow" {
		t.Errorf("past the supply's maximum: %q", got)
	}
	if got := abort(func() { CompletePayload(cross(cur), 8, testRecipient[:], 2, body) }); got != "amount-out-of-range" {
		t.Errorf("a negative wrapped claim: %q", got)
	}
	stillOpen(t, 8, 1, 2)
}

// TestCancelledClaimBody frees a cancelled claim's verified body, as for a
// completed one: only its committer's discard frees it, so the
// storage deposit behind it returns to whoever signs that call.
func TestCancelledClaimBody(cur realm, t *testing.T) {
	reset()
	body := testBody(bodyHeaderLen+200, 11)
	e := hex.EncodeToString(testRecipient[:])
	payloadClaim(cur, t, 1, 0, testTime+86400, body)
	stage(cur, t, testOperator, 1, body)
	if got := abort(func() { CommitStaged(cross(cur), 2, testRecipient[:], 1) }); got != "" {
		t.Fatalf("commit: %q", got)
	}
	paused, pauseExpiry = true, maxInt64
	testing.SetRealm(testing.NewCodeRealm(logic))
	if got := abort(func() { CancelClaim(cross(cur), 2, testRecipient, 1) }); got != "" {
		t.Fatalf("cancel: %q", got)
	}
	paused, pauseExpiry = false, 0
	testing.SetRealm(testing.NewCodeRealm(testGriefer))
	if got := abort(func() { DiscardStaged(cross(cur), 2, testRecipient[:], 1) }); got != "" {
		t.Errorf("another stager discards: %q", got)
	}
	if ok, _ := HasVerifiedBody(2, e, 1); !ok {
		t.Error("another stager's discard freed the committer's body")
	}
	testing.SetRealm(testing.NewCodeRealm(testOperator))
	if got := abort(func() { DiscardStaged(cross(cur), 2, testRecipient[:], 1) }); got != "" {
		t.Errorf("the committer discards: %q", got)
	}
	if ok, _ := HasVerifiedBody(2, e, 1); ok {
		t.Error("the committer's discard kept a cancelled claim's body")
	}
}
