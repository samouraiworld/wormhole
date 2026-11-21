package tokenbridge

import (
	"chain"
	"chain/runtime"
	"encoding/hex"
	"strconv"
	"strings"

	"gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/core"
)

// The direct entry points: governance, the logic switch, pause
// management and chain-ID confirmation. They check their own callers and
// take no logic realm's word.

const (
	governanceChain = 1
	// governanceEmitter is 0x00…04.
	governanceEmitter = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" +
		"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x04"
)

// governance applies the checks shared by every token bridge
// governance VAA up to its replay, in the reference model's order, and
// returns the VAA's digest and payload. The package's parsers check the rest.
// The payload aliases raw; the parsers copy what the vault keeps.
func governance(raw []byte) ([32]byte, []byte) {
	v := core.VerifyVAA(raw)
	if v.GuardianSetIndex != core.CurrentGuardianSetIndex() {
		panic("tokenbridge: governance-not-current-set")
	}
	if v.EmitterChain != governanceChain {
		panic("tokenbridge: governance-wrong-chain")
	}
	if string(v.EmitterAddress[:]) != governanceEmitter {
		panic("tokenbridge: governance-wrong-emitter")
	}
	if consumed.Has(string(v.Digest[:])) {
		panic("tokenbridge: governance-replay")
	}
	return v.Digest, v.Payload
}

// RegisterChain records a peer from a RegisterChain VAA (action 1), which
// anyone may present. A peer is never replaced. It stays open while paused
// and under the chain-ID freeze.
func RegisterChain(cur realm, raw []byte) {
	digest, p := governance(raw)
	peerChain, emitter, err := tokenbridge.ParseRegisterChain(p, wormholeChainID)
	fail(err)
	if peers.Has(chainKey(peerChain)) {
		panic("tokenbridge: peer-registered")
	}
	peers.Set(chainKey(peerChain), string(emitter[:]))
	consumed.Set(string(digest[:]), true)
	chain.Emit("PeerRegistered", "chain", strconv.Itoa(int(peerChain)), "emitter", hex.EncodeToString(emitter[:]))
	lapse()
}

// SetPauserAddresses assigns the three pause roles from a SetPauserAddresses
// VAA (action 4), which anyone may present. An all-zero address leaves its
// role unassigned. A change of unpauser cancels any pending confirmation. It
// stays open while paused and under the chain-ID freeze, so roles can
// rotate.
func SetPauserAddresses(cur realm, raw []byte) {
	digest, p := governance(raw)
	roles, err := tokenbridge.ParsePauserAddresses(p, wormholeChainID)
	fail(err)
	next := roleAddress(roles.Unpauser)
	rotated := next != unpauser
	pauser, freezer, unpauser = roleAddress(roles.Pauser), roleAddress(roles.Freezer), next
	consumed.Set(string(digest[:]), true)
	chain.Emit("PauserAddressesSet", "pauser", string(pauser), "freezer", string(freezer),
		"unpauser", string(unpauser))
	if rotated && pendingChainID != "" {
		cancelPending()
	}
	lapse()
}

// roleAddress is a role's address, or "" for the all-zero one.
func roleAddress(b [20]byte) address {
	if b == ([20]byte{}) {
		return ""
	}
	return encodeAddress(b)
}

// Upgrade switches the logic to its caller, the realm an UpgradeContract VAA
// (action 2) names, which presents it through its Activate. Its checks
// run in this order: the caller, the freeze, the governance checks, then the
// contract field. It stays open while paused.
func Upgrade(cur realm, raw []byte) {
	caller := cur.Previous()
	path := caller.PkgPath()
	// A code realm that is not ephemeral, not a sub-realm and not the
	// current logic.
	if !caller.IsCode() || caller.IsEphemeral() || strings.Contains(path, "#") || path == logic {
		panic("tokenbridge: upgrade-caller")
	}
	requireBound()
	digest, p := governance(raw)
	contract, err := tokenbridge.ParseUpgrade(p, wormholeChainID)
	fail(err)
	if contract != padded(addressBytes(chain.PackageAddress(path))) {
		panic("tokenbridge: upgrade-wrong-realm")
	}
	old := logic
	logic = path
	consumed.Set(string(digest[:]), true)
	chain.Emit("LogicSwitched", "old", old, "new", path)
	lapse()
}

// requireRole checks a whitepaper-0003 role: an unassigned role fails before
// any comparison.
func requireRole(role, caller address) {
	if role == "" {
		panic("tokenbridge: role-unassigned")
	}
	if caller != role {
		panic("tokenbridge: not-role")
	}
}

// Pause, by the pauser, pauses for 5 days. It never shortens a later expiry,
// so it never shortens a freeze.
func Pause(cur realm) {
	by := cur.Previous().Address()
	requireRole(pauser, by)
	expiry := blockTime() + pauseDuration
	if expiry <= pauseExpiry {
		panic("tokenbridge: pause-not-extended")
	}
	paused, pauseExpiry = true, expiry
	chain.Emit("Paused", "by", string(by), "expiry", strconv.FormatInt(expiry, 10))
	lapse()
}

// Freeze, by the freezer, pauses until the unpauser lifts it.
func Freeze(cur realm) {
	by := cur.Previous().Address()
	requireRole(freezer, by)
	paused, pauseExpiry = true, maxInt64
	chain.Emit("Frozen", "by", string(by), "expiry", strconv.FormatInt(maxInt64, 10))
	lapse()
}

// Unpause, by the unpauser, lifts a pause or a freeze. It never lifts the
// chain-ID freeze.
func Unpause(cur realm) {
	by := cur.Previous().Address()
	requireRole(unpauser, by)
	if !paused {
		panic("tokenbridge: not-paused")
	}
	paused, pauseExpiry = false, blockTime()
	chain.Emit("Unpaused", "by", string(by))
	lapse()
}

// UnpauseExpired lets anyone lift a pause once it expired.
func UnpauseExpired(cur realm) {
	if !paused {
		panic("tokenbridge: not-paused")
	}
	now := blockTime()
	if now < pauseExpiry {
		panic("tokenbridge: pause-not-expired")
	}
	paused, pauseExpiry = false, now
	chain.Emit("UnpauseExpired", "by", string(cur.Previous().Address()))
	lapse()
}

// ProposeChainID, by the unpauser while the runtime chain ID differs from
// the bound one, proposes the runtime's. It replaces any
// earlier proposal, restarting the delay and the window. The three
// confirmation steps run in every pause state.
func ProposeChainID(cur realm) {
	requireFrozen()
	requireRole(unpauser, cur.Previous().Address())
	pendingChainID, proposedAt = runtime.ChainID(), blockTime()
	chain.Emit("ChainIDProposed", "old", boundChainID, "new", pendingChainID)
}

// CancelChainID cancels the pending proposal. A live one, which equals the
// runtime chain ID, needs the freezer; anyone may cancel one that is not.
func CancelChainID(cur realm) {
	if pendingChainID == "" {
		panic("tokenbridge: no-pending-confirmation")
	}
	if runtime.ChainID() == pendingChainID {
		requireRole(freezer, cur.Previous().Address())
	}
	cancelPending()
}

// ExecuteChainID lets anyone bind the pending chain ID in the 24 hours after
// the 24-hour delay, while the runtime chain ID still equals it.
func ExecuteChainID(cur realm) {
	requireFrozen()
	if pendingChainID == "" {
		panic("tokenbridge: no-pending-confirmation")
	}
	now := blockTime()
	if now < proposedAt+confirmationDelay {
		panic("tokenbridge: confirmation-early")
	}
	if now >= proposedAt+confirmationDelay+confirmationWindow {
		panic("tokenbridge: confirmation-expired")
	}
	if runtime.ChainID() != pendingChainID {
		panic("tokenbridge: confirmation-stale")
	}
	old := boundChainID
	boundChainID, pendingChainID, proposedAt = pendingChainID, "", 0
	chain.Emit("ChainIDConfirmed", "old", old, "new", boundChainID)
}

// requireFrozen opens proposal and execution only under the chain-ID freeze.
func requireFrozen() {
	if runtime.ChainID() == boundChainID {
		panic("tokenbridge: not-frozen")
	}
}
