// Package vaa parses Wormhole VAAs and checks their guardian signatures
// against a set its caller supplies.
//
// It is stateless. The Wormhole Core realm owns the guardian sets: it calls
// Header to learn which set a VAA names, selects that set and checks its
// expiry, then calls Verify with the set's keys. A VAA value is no proof of
// verification. Anyone can build one, and Verify checks signatures against
// whatever set its caller passes, so only a result Core's VerifyVAA returns
// is verified.
//
// Errors carry stable reason codes as their text: malformed,
// signature-count-exceeds-set, no-quorum, recovery-id-out-of-range,
// signature-index-not-ascending, signature-index-out-of-range,
// invalid-signature and duplicate-signer.
package vaa

import (
	"crypto/keccak256"
	"crypto/secp256k1"
)

// VAA is a parsed VAA.
type VAA struct {
	// GuardianSetIndex is the set the header names. It is not signed, and
	// Verify checks the signatures against whatever keys its caller passes:
	// Core passes the keys it stores at this index.
	GuardianSetIndex uint32
	Timestamp        uint32
	Nonce            uint32
	EmitterChain     uint16
	EmitterAddress   [32]byte
	Sequence         uint64
	ConsistencyLevel uint8
	Payload          []byte   // a sub-slice of raw with no spare capacity, never a new allocation
	Digest           [32]byte // keccak256(keccak256(body)), the hash guardians sign
}

const (
	headerLen     = 6  // version, guardian-set index, signature count
	signatureLen  = 66 // guardian index, then r || s || recovery ID
	bodyHeaderLen = 51 // timestamp through consistency level
	keyLen        = 20 // a guardian's address
)

// reason is an error whose text is a reason code.
type reason string

func (r reason) Error() string { return string(r) }

const (
	errMalformed         reason = "malformed"
	errTooManySignatures reason = "signature-count-exceeds-set"
	errNoQuorum          reason = "no-quorum"
	errRecoveryID        reason = "recovery-id-out-of-range"
	errIndexOrder        reason = "signature-index-not-ascending"
	errIndexRange        reason = "signature-index-out-of-range"
	errInvalidSignature  reason = "invalid-signature"
	errDuplicateSigner   reason = "duplicate-signer"
)

// Header checks that raw holds a version-1 header and, for the signature
// count it declares, every signature and the body header. It returns the
// index of the guardian set the VAA names.
func Header(raw []byte) (uint32, error) {
	if len(raw) < headerLen || raw[0] != 1 {
		return 0, errMalformed
	}
	if len(raw) < headerLen+signatureLen*int(raw[5])+bodyHeaderLen {
		return 0, errMalformed
	}
	return be32(raw[1:5]), nil
}

// Verify checks raw against keys, the selected guardian set's 20-byte
// addresses packed in index order, and returns the parsed VAA. maxPayload
// bounds the payload for the VAA's class, before anything is hashed. Verify
// panics if the length of keys is not a multiple of 20.
//
// Payload aliases raw. Whoever can change raw can change Payload after
// Verify returns, so it may no longer match Digest, and persisting Payload
// persists the whole of raw: a caller copies what it keeps.
func Verify(raw []byte, keys string, maxPayload int) (VAA, error) {
	if len(keys)%keyLen != 0 {
		panic("vaa: keys are not packed 20-byte addresses")
	}
	index, err := Header(raw)
	if err != nil {
		return VAA{}, err
	}
	n := len(keys) / keyLen
	c := int(raw[5])
	if c > n {
		return VAA{}, errTooManySignatures
	}
	body := headerLen + signatureLen*c
	if len(raw)-body-bodyHeaderLen > maxPayload {
		return VAA{}, errMalformed
	}
	if c < Quorum(n) {
		return VAA{}, errNoQuorum
	}
	first := keccak256.Sum256(raw[body:])
	digest := keccak256.Sum256(first[:])
	signers := make([]string, 0, c)
	last := -1
	for i := 0; i < c; i++ {
		off := headerLen + signatureLen*i
		sig := raw[off+1 : off+signatureLen]
		if sig[64] > 1 {
			return VAA{}, errRecoveryID
		}
		guardian := int(raw[off])
		if guardian <= last {
			return VAA{}, errIndexOrder
		}
		last = guardian
		if guardian >= n {
			return VAA{}, errIndexRange
		}
		pub, ok := secp256k1.RecoverPubkey(digest[:], sig)
		if !ok {
			return VAA{}, errInvalidSignature
		}
		hash := keccak256.Sum256(pub[1:])
		signer := string(hash[12:])
		if signer != keys[guardian*keyLen:(guardian+1)*keyLen] {
			return VAA{}, errInvalidSignature
		}
		// Only a set that repeats a key lets two indices recover one signer.
		for _, s := range signers {
			if s == signer {
				return VAA{}, errDuplicateSigner
			}
		}
		signers = append(signers, signer)
	}
	b := raw[body:]
	v := VAA{
		GuardianSetIndex: index,
		Timestamp:        be32(b[0:4]),
		Nonce:            be32(b[4:8]),
		EmitterChain:     uint16(b[8])<<8 | uint16(b[9]),
		Sequence:         uint64(be32(b[42:46]))<<32 | uint64(be32(b[46:50])),
		ConsistencyLevel: b[50],
		Payload:          b[bodyHeaderLen:len(b):len(b)],
		Digest:           digest,
	}
	copy(v.EmitterAddress[:], b[10:42])
	return v, nil
}

// Quorum returns how many signatures a set of n guardians requires: more
// than two thirds of them.
func Quorum(n int) int {
	return n*2/3 + 1
}

func be32(b []byte) uint32 {
	return uint32(b[0])<<24 | uint32(b[1])<<16 | uint32(b[2])<<8 | uint32(b[3])
}
