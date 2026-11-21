// Package core is Wormhole Core on Gno. It holds the guardian sets, verifies
// VAAs for consumer realms, applies Core governance and publishes messages
// for the guardians to observe.
//
// It has no administrator, setter, pause or upgrade path. Only governance sets
// the message fee and pays out the fees collected. A rejection panics with
// "core: " followed by the reason code, and every check runs before the first
// write.
package core

import (
	"chain/banker"
	"chain/runtime"
	"strconv"
	"time"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/wormhole/vaa/v0"
)

const (
	// applicationBound bounds the payload of a VAA VerifyVAA takes. A VAA at
	// the bound still fits one transaction on a default gno node.
	applicationBound = 500_000
	// governanceBound bounds a governance payload: the largest layout, a
	// 255-key upgrade.
	governanceBound = 5_140
	// setExpiry is how long a replaced set stays valid, in seconds.
	setExpiry = 86400
	// testChainID is the placeholder Wormhole chain ID of test
	// configurations, which no production configuration carries.
	testChainID = 65535
	maxKeys     = 255
	zeroKey     = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
	// feeDenom is the message fee's denomination. Core counts and pays out
	// nothing else.
	feeDenom = "ugnot"
)

// guardianSet is a stored set. Only a non-current set can expire.
type guardianSet struct {
	keys           string // 20-byte addresses packed in index order
	expirationTime uint32
	expired        bool // set when the set is replaced below replayUntilIndex
}

// seqCell holds an emitter's next sequence. A known emitter's publication
// changes its cell in place, so the tree changes only for a new emitter.
type seqCell struct {
	next uint64
}

var (
	sets         avl.Tree // 4-byte big-endian index → *guardianSet
	currentIndex uint32
	consumed     avl.Tree // 32-byte governance digest → true
	sequences    avl.Tree // 32-byte emitter → *seqCell
	// messageFee is what a publication pays Core, in ugnot: 0 until
	// governance sets it.
	messageFee int64
	// recordedBalance is Core's ugnot balance after the last SetMessageFee,
	// the last publication under a fee, or the last payout. A publication has
	// paid its fee when the balance has grown by at least messageFee since.
	recordedBalance int64
)

func init() {
	reason := checkConfig(wormholeChainID, gnoChainID, initialSetIndex, replayUntilIndex, initialKeys,
		runtime.ChainID(), runtime.ChainHeight())
	if reason != "" {
		panic("core: " + reason)
	}
	sets.Set(setKey(initialSetIndex), &guardianSet{keys: initialKeys})
	currentIndex = initialSetIndex
}

// balance returns addr's ugnot balance, reading no other denomination.
func balance(addr address) int64 {
	return banker.NewReadonlyBanker().GetCoin(addr, feeDenom)
}

// checkConfig checks a configuration against init's rules, given the runtime's
// chain ID and height, and returns why it fails, or "".
func checkConfig(chainID uint16, gnoChain string, index, replayUntil uint32, keys,
	runtimeChain string, height int64) string {
	// From the largest index, every upgrade would overflow.
	if chainID == 0 || gnoChain == "" || index == ^uint32(0) || replayUntil < index || len(keys)%20 != 0 {
		return "invalid-configuration"
	}
	// The test chain ID and the public test keys initialize only where the
	// runtime's chain ID is one of gno's test chains, at any height. A fork
	// replays a chain's historical transactions under their source chain ID,
	// so a test Core deployed in a dev chain's history still initializes when
	// that history is replayed onto another network.
	if runtimeChain != "dev" && runtimeChain != "tendermint_test" &&
		(chainID == testChainID || holdsPublicTestKey(keys)) {
		return "invalid-configuration"
	}
	// Not at height 0, where genesis may replay past transactions under
	// their original chain IDs.
	if height > 0 && runtimeChain != gnoChain {
		return "wrong-network"
	}
	return checkKeys(keys)
}

// checkKeys returns why packed keys cannot be a guardian set, or "".
func checkKeys(keys string) string {
	if len(keys) == 0 {
		return "guardian-set-empty"
	}
	if len(keys) > maxKeys*20 {
		return "guardian-set-too-large"
	}
	for i := 0; i < len(keys); i += 20 {
		if keys[i:i+20] == zeroKey {
			return "guardian-set-zero-key"
		}
	}
	return ""
}

// holdsPublicTestKey reports whether packed keys include a key of the
// corpus's public test sets.
func holdsPublicTestKey(keys string) bool {
	for i := 0; i < len(keys); i += 20 {
		for j := 0; j < len(publicTestKeys); j += 20 {
			if keys[i:i+20] == publicTestKeys[j:j+20] {
				return true
			}
		}
	}
	return false
}

// VerifyVAA verifies raw at block time and returns it parsed. It is
// non-crossing and writes nothing: verification authorizes and consumes
// nothing. Authorizing the emitter, checking the target chain and replay
// protection are the caller's job. Payload aliases raw, so it matches Digest
// only while raw is unchanged. Whoever can change raw can change Payload
// after VerifyVAA returns, the realm that allocated raw included, during any
// later call into it. Persisting Payload persists the whole of raw. A caller
// copies what it keeps, before any call that could reach raw's owner.
func VerifyVAA(raw []byte) vaa.VAA {
	return verify(raw, applicationBound, blockTime())
}

// verify applies VerifyVAA's checks at block time now, with the payload bound of
// the VAA's class.
func verify(raw []byte, bound int, now int64) vaa.VAA {
	index, err := vaa.Header(raw)
	if err != nil {
		panic("core: " + err.Error())
	}
	set := guardianSetAt(index)
	if set == nil {
		panic("core: unknown-guardian-set")
	}
	if index != currentIndex && (set.expired || now > int64(set.expirationTime)) {
		panic("core: guardian-set-expired")
	}
	v, err := vaa.Verify(raw, set.keys, bound)
	if err != nil {
		panic("core: " + err.Error())
	}
	return v
}

func guardianSetAt(index uint32) *guardianSet {
	set := sets.Get(setKey(index))
	if set == nil {
		return nil
	}
	return set.(*guardianSet)
}

// blockTime is the block time in seconds, never negative. Expiries are
// compared at full width, so a set whose expiration time is the uint32
// maximum still expires after it.
func blockTime() int64 {
	if t := time.Now().Unix(); t > 0 {
		return t
	}
	return 0
}

// GuardianSet returns the set stored at index: its keys packed in index
// order, its expiration time, and whether it was flagged expired.
func GuardianSet(index uint32) (keys string, expirationTime uint32, expired bool, ok bool) {
	set := guardianSetAt(index)
	if set == nil {
		return "", 0, false, false
	}
	return set.keys, set.expirationTime, set.expired, true
}

// CurrentGuardianSetIndex returns the current set's index.
func CurrentGuardianSetIndex() uint32 {
	return currentIndex
}

// GovernanceConsumed reports whether a governance VAA with this digest was
// accepted.
func GovernanceConsumed(digest [32]byte) bool {
	return consumed.Has(string(digest[:]))
}

// NextSequence returns the sequence emitter's next message will carry.
func NextSequence(emitter [32]byte) uint64 {
	if cell := sequences.Get(string(emitter[:])); cell != nil {
		return cell.(*seqCell).next
	}
	return 0
}

// MessageFee returns the fee a publication pays Core, in ugnot.
func MessageFee() int64 {
	return messageFee
}

// ChainID returns this chain's Wormhole chain ID.
func ChainID() uint16 {
	return wormholeChainID
}

// GnoChainID returns the gno chain ID Core was configured for.
func GnoChainID() string {
	return gnoChainID
}

// Render shows the configuration, the current set and the message fee. It
// never echoes path.
func Render(path string) string {
	set := guardianSetAt(currentIndex)
	return "# Wormhole Core\n\n" +
		"- Wormhole chain ID: " + strconv.Itoa(int(wormholeChainID)) + "\n" +
		"- Gno chain ID: " + gnoChainID + "\n" +
		"- Current guardian set: " + strconv.FormatUint(uint64(currentIndex), 10) +
		", " + strconv.Itoa(len(set.keys)/20) + " guardians\n" +
		"- Message fee: " + strconv.FormatInt(messageFee, 10) + " ugnot\n"
}

func setKey(index uint32) string {
	return string([]byte{byte(index >> 24), byte(index >> 16), byte(index >> 8), byte(index)})
}

func be32(b []byte) uint32 {
	return uint32(b[0])<<24 | uint32(b[1])<<16 | uint32(b[2])<<8 | uint32(b[3])
}
