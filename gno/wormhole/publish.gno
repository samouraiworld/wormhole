package core

import (
	"chain"
	"crypto/sha256"
	"encoding/hex"
	"strconv"
)

// maxPublishPayload is the largest payload PublishMessage takes. Its hex is
// 4096 characters, the most chain.Emit allows in one attribute.
const maxPublishPayload = 2048

// bech32Values maps each bech32 character to its 5-bit value, and every
// other byte below 128 to 0xff.
const bech32Values = "" +
	"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" +
	"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x0f\xff\x0a\x11\x15\x14\x1a\x1e\x07\x05\xff\xff\xff\xff\xff\xff" +
	"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" +
	"\xff\x1d\xff\x18\x0d\x19\x09\x08\x17\xff\x12\x16\x1f\x1b\x13\xff\x01\x00\x03\x10\x0b\x1c\x0c\x0e\x06\x04\x02\xff\xff\xff\xff\xff"

// PublishMessage emits payload for the guardians to observe and returns its
// sequence. The emitter is the realm or user calling Core, never an
// argument. A realm cannot attach coins to a cross-realm call, so while there
// is a message fee, a publisher pays it to Core's address earlier in the same
// transaction.
func PublishMessage(cur realm, nonce uint32, payload []byte, consistency uint8) uint64 {
	caller := cur.Previous()
	// A maketx run script's /e/ path is no stable identity.
	if caller.IsEphemeral() {
		panic("core: publisher-ephemeral")
	}
	if len(payload) > maxPublishPayload {
		panic("core: payload-too-large")
	}
	// While there is a fee, it is paid when Core's ugnot balance has grown
	// by at least messageFee since it was recorded. Checked before
	// subtracting, so nothing wraps; an overpayment stays as collected fees.
	// At fee 0 the step reads and writes nothing.
	var held int64
	if messageFee > 0 {
		held = balance(cur.Address())
		if held < recordedBalance || held-recordedBalance < messageFee {
			panic("core: fee-unpaid")
		}
	}
	emitter := emitterOf(caller.PkgPath(), caller.Address())
	key := string(emitter[:])
	cell, _ := sequences.Get(key).(*seqCell)
	var seq uint64
	if cell != nil {
		seq = cell.next
	}
	if seq == ^uint64(0) {
		panic("core: sequence-exhausted")
	}
	if cell == nil {
		sequences.Set(key, &seqCell{next: 1})
	} else {
		cell.next = seq + 1
	}
	if messageFee > 0 {
		recordedBalance = held
	}
	chain.Emit("WormholeMessage",
		"emitter", hex.EncodeToString(emitter[:]),
		"sequence", strconv.FormatUint(seq, 10),
		"nonce", strconv.FormatUint(uint64(nonce), 10),
		"consistency", strconv.FormatUint(uint64(consistency), 10),
		"payload", hex.EncodeToString(payload))
	return seq
}

// emitterOf returns the 20 bytes of a caller's address, left-padded with
// zeros to 32. A code realm's address is sha256("pkgPath:" + path)[:20],
// gno's own derivation for non-ephemeral paths, sub-realms included. A
// user's address is decoded from the bech32 form the VM supplied, so its
// checksum is not checked. An address not in that form, 40 characters
// starting with g1 whose 32 data characters are lowercase bech32, fails
// with publisher-address-malformed.
func emitterOf(path string, user address) [32]byte {
	var e [32]byte
	if path != "" {
		h := sha256.Sum256([]byte("pkgPath:" + path))
		copy(e[12:], h[:20])
		return e
	}
	addr := string(user)
	if len(addr) != 40 || addr[:2] != "g1" {
		panic("core: publisher-address-malformed")
	}
	var acc uint32
	bits, j := 0, 12
	for i := 2; i < 34; i++ {
		v := byte(0xff)
		if addr[i] < 128 {
			v = bech32Values[addr[i]]
		}
		if v == 0xff {
			panic("core: publisher-address-malformed")
		}
		acc = acc<<5 | uint32(v)
		bits += 5
		if bits >= 8 {
			bits -= 8
			e[j] = byte(acc >> uint(bits))
			j++
		}
	}
	return e
}
