package vaa

import (
	"crypto/keccak256"
	"encoding/hex"
	"testing"
)

// applicationBound is Core's application payload bound.
const applicationBound = 500_000

// boundPayload returns boundByte(0) .. boundByte(n-1), where boundByte(i) is
// byte(i*31 + 7), as in testBoundVectors' payloads. The pattern repeats every
// 256 bytes, so doubling one period builds it without a byte-by-byte loop.
func boundPayload(n int) []byte {
	b := make([]byte, 256)
	for i := range b {
		b[i] = byte(i*31 + 7)
	}
	for len(b) < n {
		b = append(b, b...)
	}
	return b[:n]
}

func unhex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("bad hex: %v", err)
	}
	return b
}

func code(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

// corpusVAA returns a corpus VAA and the packed keys of the set it runs
// against.
func corpusVAA(t *testing.T, name string) ([]byte, string) {
	t.Helper()
	for _, v := range testVectors {
		if v.name == name {
			return unhex(t, v.vaa), string(unhex(t, testSets[v.set]))
		}
	}
	t.Fatalf("no generated vector %s", name)
	return nil, ""
}

// sameBody reports whether got holds the SDK's decoding of a body header and
// its digest. Callers compare the payload themselves.
func sameBody(got VAA, timestamp, nonce uint32, chain uint16, emitter string, sequence uint64,
	consistency uint8, digest string) bool {
	return got.Timestamp == timestamp && got.Nonce == nonce && got.EmitterChain == chain &&
		hex.EncodeToString(got.EmitterAddress[:]) == emitter && got.Sequence == sequence &&
		got.ConsistencyLevel == consistency && hex.EncodeToString(got.Digest[:]) == digest
}

func TestCorpusVectors(t *testing.T) {
	for _, v := range testVectors {
		raw := unhex(t, v.vaa)
		index, err := Header(raw)
		if code(err) != v.header || (err == nil && index != v.index) {
			t.Errorf("%s: Header gives %d, %q; want %d, %q", v.name, index, code(err), v.index, v.header)
		}
		got, err := Verify(raw, string(unhex(t, testSets[v.set])), applicationBound)
		if code(err) != v.reason {
			t.Errorf("%s: Verify gives %q, want %q", v.name, code(err), v.reason)
			continue
		}
		if err == nil && (got.GuardianSetIndex != v.index || hex.EncodeToString(got.Payload) != v.payload ||
			!sameBody(got, v.timestamp, v.nonce, v.emitterChain, v.emitter, v.sequence, v.consistency, v.digest)) {
			t.Errorf("%s: Verify's fields differ from the SDK's: %+v", v.name, got)
		}
	}
}

func TestHeaderMalformed(t *testing.T) {
	raw, keys := corpusVAA(t, "quorum-13-of-19/0")
	short := 6 + 66*13 + 51 // header, 13 signatures and the body header
	for _, tc := range []struct {
		name string
		raw  []byte
	}{
		{"nil", nil},
		{"five bytes", raw[:5]},
		{"one byte short of the body header", raw[:short-1]},
		{"version 0", withByte(raw, 0, 0)},
		{"version 2", withByte(raw, 0, 2)},
	} {
		if _, err := Header(tc.raw); code(err) != "malformed" {
			t.Errorf("%s: Header gives %q", tc.name, code(err))
		}
		if _, err := Verify(tc.raw, keys, applicationBound); code(err) != "malformed" {
			t.Errorf("%s: Verify gives %q", tc.name, code(err))
		}
	}
	// An empty payload is well formed; the shortened body no longer matches
	// its signatures.
	if index, err := Header(raw[:short]); err != nil || index != 3 {
		t.Errorf("empty payload: Header gives %d, %q", index, code(err))
	}
	if _, err := Verify(raw[:short], keys, applicationBound); code(err) != "invalid-signature" {
		t.Errorf("empty payload: Verify gives %q", code(err))
	}
	// A count byte of 128 or more is read unsigned here too: 171 signatures,
	// one byte short of the body header.
	big := unhex(t, testMaxVAA)
	bigShort := big[:6+66*171+50]
	if _, err := Header(bigShort); code(err) != "malformed" {
		t.Errorf("171 signatures, one byte short: Header gives %q", code(err))
	}
	if _, err := Verify(bigShort, string(unhex(t, testSets["max255"])), applicationBound); code(err) != "malformed" {
		t.Errorf("171 signatures, one byte short: Verify gives %q", code(err))
	}
}

// TestCheckOrder pins where the payload bound
// sits in the order. The reference model has no such bound, so
// TestFaultVectors cannot pin it.
func TestCheckOrder(t *testing.T) {
	raw, keys := corpusVAA(t, "quorum-13-of-19/0")
	// 13 signatures against 12 keys, payload over a zero bound: the count first.
	if _, err := Verify(raw, keys[:12*20], 0); code(err) != "signature-count-exceeds-set" {
		t.Errorf("count before bound: %q", code(err))
	}
	// 12 signatures of 19, payload over a zero bound: the bound before quorum.
	below, _ := corpusVAA(t, "below-quorum-12/0")
	if _, err := Verify(below, keys, 0); code(err) != "malformed" {
		t.Errorf("bound before quorum: %q", code(err))
	}
	// A recovery-ID fault, payload over a zero bound: the bound before any
	// signature.
	if _, err := Verify(withByte(raw, 6+66*4+65, 2), keys, 0); code(err) != "malformed" {
		t.Errorf("bound before signatures: %q", code(err))
	}
}

// TestFaultVectors pins the rest of the order, and that entries past the
// quorum-th are checked (TestLargestSet breaks the last of 171): each
// generated VAA breaks one or two rules, and the reference model fixes which
// one is reported.
func TestFaultVectors(t *testing.T) {
	for _, v := range testFaultVectors {
		raw, _ := corpusVAA(t, v.base)
		for _, p := range v.patches {
			copy(raw[p.offset:], unhex(t, p.bytes))
		}
		if v.length > 0 {
			raw = raw[:v.length]
		}
		if _, err := Verify(raw, string(unhex(t, testSets[v.set])), applicationBound); code(err) != v.reason {
			t.Errorf("%s: Verify gives %q, want %q", v.name, code(err), v.reason)
		}
	}
}

// TestDuplicateSigner repeats a key in the set and has two entries recover
// it: two entries apart from each other, the same signer through its other
// valid signature, and both entries past the quorum-th.
func TestDuplicateSigner(t *testing.T) {
	raw, keys := corpusVAA(t, "quorum-13-of-19/0")
	set := keys[:9*20] + keys[3*20:4*20] + keys[10*20:]
	dup := append([]byte(nil), raw...)
	copy(dup[6+66*9+1:6+66*10], raw[6+66*3+1:6+66*4])
	if _, err := Verify(dup, set, applicationBound); code(err) != "duplicate-signer" {
		t.Errorf("non-adjacent duplicate: %q", code(err))
	}
	// Entry 3's malleated twin (r, n-s, v^1) is a valid signature by key 3
	// with other bytes, so duplicates are found by signer, not by bytes.
	alone := append([]byte(nil), raw...)
	copy(alone[6+66*3+1:6+66*4], malleate(raw, 3))
	if _, err := Verify(alone, keys, applicationBound); err != nil {
		t.Fatalf("malleated entry 3 in place: %q", code(err))
	}
	twin := append([]byte(nil), raw...)
	copy(twin[6+66*9+1:6+66*10], malleate(raw, 3))
	if _, err := Verify(twin, set, applicationBound); code(err) != "duplicate-signer" {
		t.Errorf("malleated duplicate: %q", code(err))
	}
	// Key 17 repeated at index 18 of 19: both past the quorum-th entry.
	all, keys19 := corpusVAA(t, "all-19-of-19/0")
	late := append([]byte(nil), all...)
	copy(late[6+66*18+1:6+66*19], all[6+66*17+1:6+66*18])
	if _, err := Verify(late, keys19[:18*20]+keys19[17*20:18*20], applicationBound); code(err) != "duplicate-signer" {
		t.Errorf("duplicate past quorum: %q", code(err))
	}
}

// curveOrder is the secp256k1 group order n, big-endian.
var curveOrder = []byte{0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
	0xff, 0xfe, 0xba, 0xae, 0xdc, 0xe6, 0xaf, 0x48, 0xa0, 0x3b, 0xbf, 0xd2, 0x5e, 0x8c, 0xd0, 0x36, 0x41, 0x41}

// malleate returns entry src of raw as (r, n-s, v^1), the other signature
// of the same signer over the same digest.
func malleate(raw []byte, src int) []byte {
	out := append([]byte(nil), raw[6+66*src+1:6+66*src+66]...)
	borrow := 0
	for i := 31; i >= 0; i-- {
		d := int(curveOrder[i]) - int(out[32+i]) - borrow
		borrow = 0
		if d < 0 {
			d += 256
			borrow = 1
		}
		out[32+i] = byte(d)
	}
	out[64] ^= 1
	return out
}

// TestScalarAtCurveOrder sets r or s of an entry to n, which no valid
// signature carries.
func TestScalarAtCurveOrder(t *testing.T) {
	raw, keys := corpusVAA(t, "quorum-13-of-19/0")
	for name, off := range map[string]int{"r of entry 9": 6 + 66*9 + 1, "s of entry 4": 6 + 66*4 + 1 + 32} {
		bad := append([]byte(nil), raw...)
		copy(bad[off:off+32], curveOrder)
		if _, err := Verify(bad, keys, applicationBound); code(err) != "invalid-signature" {
			t.Errorf("%s set to n: %q", name, code(err))
		}
	}
}

// TestNearMissKey puts at index 0 a key one bit away from signer 0's
// address, in each of the 20 bytes: entry 0 must stay invalid.
func TestNearMissKey(t *testing.T) {
	raw, keys := corpusVAA(t, "quorum-13-of-19/0")
	for b := 0; b < keyLen; b++ {
		k := []byte(keys)
		k[b] ^= 0x01
		if _, err := Verify(raw, string(k), applicationBound); code(err) != "invalid-signature" {
			t.Errorf("key 0 differing in byte %d: %q", b, code(err))
		}
	}
}

// TestIndexBackwardsAfterGap drops entry 4 of all-19-of-19 and swaps the
// next two: indices 0,1,2,3,6,5,7..18, where 5 follows 6.
func TestIndexBackwardsAfterGap(t *testing.T) {
	raw, keys := corpusVAA(t, "all-19-of-19/0")
	out := append([]byte(nil), raw[:6]...)
	out[5] = 18
	for _, i := range []int{0, 1, 2, 3, 6, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18} {
		out = append(out, raw[6+66*i:6+66*(i+1)]...)
	}
	out = append(out, raw[6+66*19:]...)
	if _, err := Verify(out, keys, applicationBound); code(err) != "signature-index-not-ascending" {
		t.Errorf("index 5 after index 6: %q", code(err))
	}
}

// TestIndexAboveSetSize names indices at and far above the set's size.
func TestIndexAboveSetSize(t *testing.T) {
	raw, keys := corpusVAA(t, "quorum-13-of-19/0")
	for _, index := range []byte{19, 20, 255} {
		if _, err := Verify(withByte(raw, 6+66*12, index), keys, applicationBound); code(err) != "signature-index-out-of-range" {
			t.Errorf("index %d of 19 keys: %q", index, code(err))
		}
	}
}

// TestFailedRecoveryMatchesNoKey puts the address of the all-zero public key,
// which a failed recovery returns, into the set: a signature that does not
// recover must still be invalid at that index.
func TestFailedRecoveryMatchesNoKey(t *testing.T) {
	raw, keys := corpusVAA(t, "quorum-13-of-19/0")
	zero := keccak256.Sum256(make([]byte, 64))
	set := string(zero[12:]) + keys[20:]
	unrecoverable := append([]byte(nil), raw...)
	for i := 6 + 1; i < 6+66; i++ { // signature 0's r, s and recovery ID
		unrecoverable[i] = 0
	}
	if _, err := Verify(unrecoverable, set, applicationBound); code(err) != "invalid-signature" {
		t.Errorf("failed recovery: %q", code(err))
	}
}

// TestPayloadBound runs signed VAAs at the bound's edges, empty, 500,000
// and 500,001 bytes, under the bound and with the reason testBoundVectors
// records for each.
func TestPayloadBound(t *testing.T) {
	_, keys := corpusVAA(t, "quorum-13-of-19/0")
	// The vectors must be an accepted empty payload, and straddle the bound:
	// one accepted at it, one refused a byte over it.
	if len(testBoundVectors) != 3 || testBoundVectors[0].length != 0 || testBoundVectors[0].reason != "" ||
		testBoundVectors[1].length != testBoundVectors[1].bound ||
		testBoundVectors[1].reason != "" || testBoundVectors[2].length != testBoundVectors[2].bound+1 ||
		testBoundVectors[2].reason != "malformed" {
		t.Fatalf("bound vectors do not sit at the bound: %d", len(testBoundVectors))
	}
	for _, b := range testBoundVectors {
		raw := append(unhex(t, b.signatures), unhex(t, b.bodyStart)...)
		raw = append(raw, boundPayload(b.length)...)
		got, err := Verify(raw, keys, b.bound)
		if code(err) != b.reason {
			t.Errorf("%d bytes: Verify gives %q, want %q", b.length, code(err), b.reason)
			continue
		}
		if err != nil {
			continue
		}
		if got.GuardianSetIndex != 3 || len(got.Payload) != b.length ||
			!sameBody(got, b.timestamp, b.nonce, b.emitterChain, b.emitter, b.sequence, b.consistency, b.digest) {
			t.Errorf("%d bytes: Verify gives %q, fields %d %d %d %d %d, payload length %d", b.length, code(err),
				got.Timestamp, got.Nonce, got.EmitterChain, got.Sequence, got.ConsistencyLevel, len(got.Payload))
		}
		if b.length > 0 {
			if _, err := Verify(raw, keys, b.length-1); code(err) != "malformed" {
				t.Errorf("%d bytes under a bound one smaller: %q", b.length, code(err))
			}
		}
	}
}

func TestQuorumFromSetSize(t *testing.T) {
	for n, want := range map[int]int{0: 1, 1: 1, 2: 2, 3: 3, 4: 3, 18: 13, 19: 13, 255: 171} {
		if got := Quorum(n); got != want {
			t.Errorf("Quorum(%d) = %d, want %d", n, got, want)
		}
	}
	// An empty set verifies nothing.
	empty := append([]byte{1, 0, 0, 0, 3, 0}, make([]byte, 51)...)
	if _, err := Verify(empty, "", applicationBound); code(err) != "no-quorum" {
		t.Errorf("no signatures, no keys: %q", code(err))
	}
	raw, keys := corpusVAA(t, "quorum-13-of-19/0")
	if _, err := Verify(raw, "", applicationBound); code(err) != "signature-count-exceeds-set" {
		t.Errorf("signatures, no keys: %q", code(err))
	}
	// Quorum and the index range follow the set's size, not 19.
	twenty := keys + string(unhex(t, testSets["set4"]))[:20]
	if _, err := Verify(raw, twenty, applicationBound); code(err) != "no-quorum" {
		t.Errorf("13 of 20: %q", code(err))
	}
	below, _ := corpusVAA(t, "below-quorum-12/0")
	if _, err := Verify(below, keys[:15*20], applicationBound); err != nil {
		t.Errorf("12 of 15: %q", code(err))
	}
	if _, err := Verify(withByte(raw, 6+66*12, 18), keys[:18*20], applicationBound); code(err) != "signature-index-out-of-range" {
		t.Errorf("index 18 of 18 keys: %q", code(err))
	}
}

// TestLargestSet verifies the quorum of a 255-key set, 171 signatures, so
// counts and guardian indices of 128 and above are read as unsigned.
func TestLargestSet(t *testing.T) {
	raw := unhex(t, testMaxVAA)
	keys := string(unhex(t, testSets["max255"]))
	// Signed at indices 84..254: a quorum that skips the first guardians.
	if raw[6] != 84 || raw[6+66*170] != 254 {
		t.Fatalf("largest-set VAA signed from index %d to %d", raw[6], raw[6+66*170])
	}
	if got, err := Verify(raw, keys, applicationBound); err != nil || got.GuardianSetIndex != 9 {
		t.Errorf("171 of 255: %q, set %d", code(err), got.GuardianSetIndex)
	}
	// Drop the last signature: 170 of 255 is below quorum.
	short := append([]byte{1, 0, 0, 0, 9, 170}, raw[6:6+66*170]...)
	short = append(short, raw[6+66*171:]...)
	if _, err := Verify(short, keys, applicationBound); code(err) != "no-quorum" {
		t.Errorf("170 of 255: %q", code(err))
	}
	// Break the last entry, the 171st: the loop reaches it.
	if _, err := Verify(withByte(raw, 6+66*170+65, 2), keys, applicationBound); code(err) != "recovery-id-out-of-range" {
		t.Errorf("recovery ID 2 on entry 170: %q", code(err))
	}
	unrecoverable := append([]byte(nil), raw...)
	for i := 6 + 66*170 + 1; i < 6+66*171; i++ {
		unrecoverable[i] = 0
	}
	if _, err := Verify(unrecoverable, keys, applicationBound); code(err) != "invalid-signature" {
		t.Errorf("unrecoverable entry 170: %q", code(err))
	}
}

// TestSetIndexAllBytes renames a VAA's guardian set to 0xa1b2c303. The
// header is not signed, so Verify still accepts it against set 3's keys, and
// both functions must read all four bytes of the index.
func TestSetIndexAllBytes(t *testing.T) {
	raw, keys := corpusVAA(t, "quorum-13-of-19/0")
	raw[1], raw[2], raw[3] = 0xa1, 0xb2, 0xc3
	if index, err := Header(raw); err != nil || index != 0xa1b2c303 {
		t.Errorf("Header gives %d, %q", index, code(err))
	}
	if got, err := Verify(raw, keys, applicationBound); err != nil || got.GuardianSetIndex != 0xa1b2c303 {
		t.Errorf("Verify gives %d, %q", got.GuardianSetIndex, code(err))
	}
}

func TestPayloadAliasesRaw(t *testing.T) {
	raw, keys := corpusVAA(t, "quorum-13-of-19/0")
	got, err := Verify(raw, keys, applicationBound)
	if err != nil {
		t.Fatalf("Verify: %q", code(err))
	}
	last := len(raw) - 1
	raw[last] ^= 0xff
	if got.Payload[len(got.Payload)-1] != raw[last] {
		t.Error("Payload does not alias raw")
	}
}

// TestPayloadHasNoSpareCapacity verifies a VAA held in a larger buffer:
// appending to Payload must not write past the VAA into that buffer.
func TestPayloadHasNoSpareCapacity(t *testing.T) {
	raw, keys := corpusVAA(t, "quorum-13-of-19/0")
	buf := make([]byte, len(raw), len(raw)+1)
	copy(buf, raw)
	got, err := Verify(buf, keys, applicationBound)
	if err != nil {
		t.Fatalf("Verify: %q", code(err))
	}
	_ = append(got.Payload, 0xaa)
	if cap(got.Payload) != len(got.Payload) || buf[:len(buf)+1][len(buf)] == 0xaa {
		t.Error("Payload carries the buffer's spare capacity")
	}
}

func TestUnpackedKeysPanic(t *testing.T) {
	raw, keys := corpusVAA(t, "quorum-13-of-19/0")
	defer func() {
		if r := recover(); r != "vaa: keys are not packed 20-byte addresses" {
			t.Errorf("recovered %v", r)
		}
	}()
	Verify(raw, keys[:len(keys)-1], applicationBound)
	t.Error("Verify accepted keys that are not packed 20-byte addresses")
}

// withByte returns a copy of b with b[i] = v.
func withByte(b []byte, i int, v byte) []byte {
	c := append([]byte(nil), b...)
	c[i] = v
	return c
}
