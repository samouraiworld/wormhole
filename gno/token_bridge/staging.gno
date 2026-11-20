package tokenbridge

import (
	"strings"
)

// Payload-3 completion. A body too large for one transaction is
// staged in parts: each stager writes, commits and discards only its own
// buffer, so a griefer can spoil only its own. The recipient then completes
// at the fixed path CompletePayload, across logic switches.

// StageChunk writes chunk at index in the caller's buffer for a payload-3
// claim. Chunks are 65,536 bytes, except the last, which holds the rest of
// the claim's body length. A retry overwrites the same chunk.
func StageChunk(cur realm, emitterChain uint16, emitterAddress []byte, sequence uint64, index int, chunk []byte) {
	gate()
	stager := addressBytes(cur.Previous().Address())
	key := replayKey(emitterChain, emitterAddress, sequence)
	c := stageableClaim(key)
	if index < 0 || index >= chunkCount(c.bodyLen) || len(chunk) != chunkLen(c.bodyLen, index) {
		panic("tokenbridge: stage-bad-chunk")
	}
	staged.Set(chunkKey(key, stager, index), string(chunk))
	lapse()
}

// CommitStaged makes the caller's complete buffer the claim's verified body,
// if its double keccak matches, and frees the buffer. It never replaces
// another stager's body.
func CommitStaged(cur realm, emitterChain uint16, emitterAddress []byte, sequence uint64) {
	gate()
	caller := cur.Previous().Address()
	stager := addressBytes(caller)
	key := replayKey(emitterChain, emitterAddress, sequence)
	c := stageableClaim(key)
	n := chunkCount(c.bodyLen)
	parts := make([]string, n)
	for i := range parts {
		chunk := staged.Get(chunkKey(key, stager, i))
		if chunk == nil {
			panic("tokenbridge: stage-incomplete")
		}
		parts[i] = chunk.(string)
	}
	body := strings.Join(parts, "")
	if doubleKeccak([]byte(body)) != c.digest {
		panic("tokenbridge: claim-body-mismatch")
	}
	verifiedBodies.Set(key, &verifiedBody{body: body, committer: caller})
	for i := 0; i < n; i++ {
		staged.Remove(chunkKey(key, stager, i))
	}
	lapse()
}

// DiscardStaged frees the caller's buffer, also after another stager's body
// was committed. Once the claim is completed or cancelled, it also frees the
// verified body if the caller committed it, so its storage deposit returns
// to whoever frees it.
func DiscardStaged(cur realm, emitterChain uint16, emitterAddress []byte, sequence uint64) {
	gate()
	caller := cur.Previous().Address()
	stager := addressBytes(caller)
	key := replayKey(emitterChain, emitterAddress, sequence)
	c := claimAt(key)
	if c == nil {
		panic("tokenbridge: claim-not-found")
	}
	for i := 0; i < chunkCount(c.bodyLen); i++ {
		staged.Remove(chunkKey(key, stager, i))
	}
	if v := verifiedBodies.Get(key); c.state != claimOpen && v != nil && v.(*verifiedBody).committer == caller {
		verifiedBodies.Remove(key)
	}
	lapse()
}

// CompletePayload completes a released payload-3 claim for its recipient,
// the only caller it accepts, and pays the recipient the whole amount.
// body is the whole body; an empty one stands for the verified body staged
// in parts. It returns the payload-3 message, body[51:], as a string, which
// the recipient converts in its own realm. It leaves any verified body to
// its committer to free.
func CompletePayload(cur realm, emitterChain uint16, emitterAddress []byte, sequence uint64, body []byte) string {
	gate()
	key := replayKey(emitterChain, emitterAddress, sequence)
	c := openClaim(key, 3)
	requireReleased(c)
	if cur.Previous().Address() != c.recipient {
		panic("tokenbridge: not-recipient")
	}
	var b string
	if len(body) == 0 {
		v := verifiedBodies.Get(key)
		if v == nil {
			panic("tokenbridge: stage-incomplete")
		}
		b = v.(*verifiedBody).body
	} else {
		if doubleKeccak(body) != c.digest {
			panic("tokenbridge: claim-body-mismatch")
		}
		b = string(body)
	}
	// A VAA body is longer than its header; a logic's claim might not be.
	if len(b) < bodyHeaderLen {
		panic("tokenbridge: claim-body-mismatch")
	}
	w := checkPayment(c.asset, c.amount)
	c.state = claimCompleted
	pay(cur, w, c.recipient, c.amount)
	transferEvent("ClaimCompleted", emitterChain, emitterAddress, sequence)
	lapse()
	return b[bodyHeaderLen:]
}

// stageableClaim returns the payload-3 claim at key, which must be open and
// have no verified body yet.
func stageableClaim(key string) *claim {
	c := openClaim(key, 3)
	if verifiedBodies.Has(key) {
		panic("tokenbridge: body-already-verified")
	}
	return c
}

// chunkCount is the number of chunks of a body of bodyLen bytes, or 0 for a
// length no verified VAA's body has, which only a faulty logic's claim could
// carry: none of its chunks can then be staged.
func chunkCount(bodyLen int) int {
	if bodyLen <= 0 || bodyLen > maxBodyLen {
		return 0
	}
	return 1 + (bodyLen-1)/chunkSize
}

// chunkLen is the length of chunk index of such a body.
func chunkLen(bodyLen, index int) int {
	if index == chunkCount(bodyLen)-1 {
		return bodyLen - chunkSize*index
	}
	return chunkSize
}

// chunkKey is a chunk's key: the replay key, the stager's 20 bytes, then
// the index in 4 bytes, big-endian.
func chunkKey(key string, stager [20]byte, index int) string {
	return key + string(stager[:]) + string([]byte{byte(index >> 24), byte(index >> 16), byte(index >> 8), byte(index)})
}
