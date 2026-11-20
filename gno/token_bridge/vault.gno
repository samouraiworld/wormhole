// Package tokenbridge is the vault of gno's Wormhole token bridge. Its address
// is the bridge's emitter, so its path never changes. It holds every value and
// record that must survive a logic switch: the GNOT escrow, the wrapped assets,
// the peers, the redeemed transfers and their claims, and the pause and
// chain-ID state. A replaceable logic realm, which guardians name by
// governance, parses inbound VAAs and applies the bridge's policy.
//
// The vault builds every message it publishes: a transfer in the call that
// locks or burns its amount, and GNOT's AssetMeta from its configuration. A
// rejection panics with "tokenbridge: " followed by the reason code, and every
// check runs before the first write.
package tokenbridge

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"crypto/bech32"
	"crypto/keccak256"
	"strings"
	"time"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/core"
)

const (
	// testChainID is the placeholder Wormhole chain ID of test
	// configurations, as for Core.
	testChainID  = 65535
	gnotDecimals = 6
	// chunkSize is the size of every staged chunk of a payload-3 body but
	// the last.
	chunkSize = 65536
	// bodyHeaderLen is the length of a VAA body before its payload:
	// timestamp, nonce, emitter chain, emitter, sequence and consistency.
	bodyHeaderLen = 51
	// maxBodyLen is the longest body a verified VAA can have: the header and
	// Core's application bound on its payload.
	maxBodyLen         = bodyHeaderLen + 500_000
	pauseDuration      = 5 * 86400
	confirmationDelay  = 86400
	confirmationWindow = 86400
	maxInt64           = 1<<63 - 1
)

// The states of a claim.
const (
	claimOpen = iota
	claimCompleted
	claimCancelled
)

// claim is a recorded transfer the logic did not pay at once: the
// fields of the tokenbridge.Claim the logic passed, copied, plus whether it
// was delayed and its state.
type claim struct {
	digest      [32]byte
	payloadID   uint8
	recipient   address
	asset       tokenbridge.Origin
	amount      int64
	fee         int64
	bodyLen     int
	releaseTime int64
	delayed     bool
	state       int
}

// verifiedBody is a committed payload-3 body and who committed it.
type verifiedBody struct {
	body      string
	committer address
}

// wrappedAsset is a foreign asset's grc20 wrapper.
type wrappedAsset struct {
	origin tokenbridge.Origin
	token  *grc20.Token
	ledger *grc20.PrivateLedger
	meta   [32]byte // the digest of the AssetMeta that created it
}

var (
	logic           string
	boundChainID    string
	pendingChainID  string
	proposedAt      int64
	paused          bool
	pauseExpiry     int64
	pauser          address // "" while unassigned, as freezer and unpauser
	freezer         address
	unpauser        address
	peers           avl.Tree // 2-byte chain ID → 32-byte emitter
	consumed        avl.Tree // 32-byte governance digest → true
	redeemed        avl.Tree // 42-byte replay key → true
	claims          avl.Tree // replay key → *claim, never deleted
	staged          avl.Tree // replay key ‖ stager (20 bytes) ‖ chunk index (4) → chunk
	verifiedBodies  avl.Tree // replay key → *verifiedBody
	lockedGNOT      int64    // ugnot
	recordedBalance int64    // the ugnot balance after the last GNOT operation
	wrapped         avl.Tree // 34-byte origin key → *wrappedAsset
	originBySymbol  avl.Tree // grc20 symbol → origin key
	tokenIDs        seqid.ID
)

func init(cur realm) {
	reason := checkConfig(wormholeChainID, gnoChainID, initialLogic, gnotSymbol, gnotName,
		core.ChainID(), core.GnoChainID(), runtime.ChainID(), runtime.ChainHeight())
	if reason != "" {
		panic("tokenbridge: " + reason)
	}
	logic = initialLogic
	boundChainID = gnoChainID
	// Coins sent to the vault's address before deployment never fund a lock.
	recordedBalance = balanceOf(cur.Address())
}

// checkConfig checks a configuration against init's rules, given Core's chain IDs
// and the runtime's chain ID and height, and returns why it fails, or "".
// Core's own configuration checks come first, so a gno chain ID other than the
// runtime's is wrong-network, as for Core.
func checkConfig(chainID uint16, gnoChain, initial, symbol, name string, coreChain uint16, coreGno string,
	runtimeChain string, height int64,
) string {
	if chainID == 0 || gnoChain == "" {
		return "invalid-configuration"
	}
	if chainID == testChainID && runtimeChain != "dev" && runtimeChain != "tendermint_test" {
		return "invalid-configuration"
	}
	if height > 0 && runtimeChain != gnoChain {
		return "wrong-network"
	}
	if chainID != coreChain || gnoChain != coreGno || !realmPath(initial) {
		return "invalid-configuration"
	}
	// GNOT's AssetMeta must always be buildable.
	if _, ok := tokenbridge.Pad32(symbol); !ok {
		return "invalid-configuration"
	}
	if _, ok := tokenbridge.Pad32(name); !ok {
		return "invalid-configuration"
	}
	return ""
}

// realmPath reports whether path names a code realm the logic switch could
// also install: <domain>/r/<name>, which no maketx run script's /e/ path and
// no sub-realm's # path is.
func realmPath(path string) bool {
	parts := strings.SplitN(path, "/", 3)
	return len(parts) == 3 && parts[0] != "" && parts[1] == "r" && parts[2] != "" && !strings.Contains(path, "#")
}

// requireLogic is the first check of every logic-only operation.
func requireLogic(cur realm) {
	if cur.Previous().PkgPath() != logic {
		panic("tokenbridge: not-current-logic")
	}
}

// gate is the value gate: not paused, and not under the chain-ID
// freeze.
func gate() {
	if paused {
		panic("tokenbridge: bridge-paused")
	}
	requireBound()
}

// requireBound is the gate's chain-ID half.
func requireBound() {
	if runtime.ChainID() != boundChainID {
		panic("tokenbridge: bridge-frozen")
	}
}

// lapse clears a pending chain-ID proposal that is not live, one whose chain
// ID is not the runtime's. Every state-changing call but the three
// confirmation steps calls it last, after its checks; reads never do.
func lapse() {
	if pendingChainID != "" && runtime.ChainID() != pendingChainID {
		cancelPending()
	}
}

func cancelPending() {
	cancelled := pendingChainID
	pendingChainID, proposedAt = "", 0
	chain.Emit("ChainIDCancelled", "old", boundChainID, "new", cancelled)
}

// blockTime is the block time in seconds, never negative.
func blockTime() int64 {
	if t := time.Now().Unix(); t > 0 {
		return t
	}
	return 0
}

// balanceOf reads one ugnot balance.
func balanceOf(a address) int64 {
	return banker.NewReadonlyBanker().GetCoin(a, "ugnot")
}

// bech32Values maps each bech32 character to its 5-bit value, and every
// other byte below 128 to 0xff, as Core's lookup table does.
const bech32Values = "" +
	"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" +
	"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x0f\xff\x0a\x11\x15\x14\x1a\x1e\x07\x05\xff\xff\xff\xff\xff\xff" +
	"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff" +
	"\xff\x1d\xff\x18\x0d\x19\x09\x08\x17\xff\x12\x16\x1f\x1b\x13\xff\x01\x00\x03\x10\x0b\x1c\x0c\x0e\x06\x04\x02\xff\xff\xff\xff\xff"

// decodeAddress returns the 20 bytes of an address in the form the VM
// supplies: 40 characters starting with g1, whose 32 data characters are
// lowercase bech32. The checksum is not checked.
func decodeAddress(a address) ([20]byte, bool) {
	var b [20]byte
	s := string(a)
	if len(s) != 40 || s[:2] != "g1" {
		return b, false
	}
	var acc uint32
	bits, j := 0, 0
	for i := 2; i < 34; i++ {
		v := byte(0xff)
		if s[i] < 128 {
			v = bech32Values[s[i]]
		}
		if v == 0xff {
			return b, false
		}
		acc = acc<<5 | uint32(v)
		bits += 5
		if bits >= 8 {
			bits -= 8
			b[j] = byte(acc >> uint(bits))
			j++
		}
	}
	return b, true
}

// addressBytes is decodeAddress for a caller, which fails with
// caller-address-malformed.
func addressBytes(a address) [20]byte {
	b, ok := decodeAddress(a)
	if !ok {
		panic("tokenbridge: caller-address-malformed")
	}
	return b
}

// padded left-pads 20 address bytes to 32.
func padded(b [20]byte) [32]byte {
	var p [32]byte
	copy(p[12:], b[:])
	return p
}

// encodeAddress returns 20 bytes as a gno address.
func encodeAddress(b [20]byte) address {
	s, err := bech32.EncodeFromBase256("g", b[:])
	if err != nil {
		panic(err) // 20 bytes always encode
	}
	return address(s)
}

func chainKey(id uint16) string {
	return string([]byte{byte(id >> 8), byte(id)})
}

// replayKey builds the replay key a direct entry point's caller names. An
// emitter that is not 32 bytes long gives "", which no transfer has.
func replayKey(emitterChain uint16, emitter []byte, sequence uint64) string {
	var e [32]byte
	if len(emitter) != 32 {
		return ""
	}
	copy(e[:], emitter)
	return tokenbridge.ReplayKey(emitterChain, e, sequence)
}

// doubleKeccak is a VAA body's digest.
func doubleKeccak(body []byte) [32]byte {
	h := keccak256.Sum256(body)
	return keccak256.Sum256(h[:])
}

func gnotOrigin() tokenbridge.Origin {
	return tokenbridge.Origin{Chain: wormholeChainID, Address: tokenbridge.GNOTAddress()}
}

func isGNOT(o tokenbridge.Origin) bool {
	return o == gnotOrigin()
}

func wrappedAt(originKey string) *wrappedAsset {
	if w := wrapped.Get(originKey); w != nil {
		return w.(*wrappedAsset)
	}
	return nil
}

func wrappedBySymbol(symbol string) *wrappedAsset {
	if key := originBySymbol.Get(symbol); key != nil {
		return wrappedAt(key.(string))
	}
	return nil
}

func claimAt(key string) *claim {
	if c := claims.Get(key); c != nil {
		return c.(*claim)
	}
	return nil
}

// openClaim returns the claim at key, which must exist, have payload type
// id and be open.
func openClaim(key string, id uint8) *claim {
	c := claimAt(key)
	if c == nil {
		panic("tokenbridge: claim-not-found")
	}
	if c.payloadID != id {
		panic("tokenbridge: claim-wrong-type")
	}
	requireOpen(c)
	return c
}

func requireOpen(c *claim) {
	switch c.state {
	case claimCompleted:
		panic("tokenbridge: claim-completed")
	case claimCancelled:
		panic("tokenbridge: claim-cancelled")
	}
}

// fail panics with a package error's reason code.
func fail(err error) {
	if err != nil {
		panic("tokenbridge: " + err.Error())
	}
}
