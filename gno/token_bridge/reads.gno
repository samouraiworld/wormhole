package tokenbridge

import (
	"chain/runtime"
	"encoding/hex"
	"strconv"
	"strings"
	"time"

	"gno.land/p/nt/markdown/sanitize/v0"
	"gno.land/p/wormhole/tokenbridge/v0"
)

// The read API. These are non-crossing, change nothing, and return
// only integers, booleans and strings, with 32-byte values as 64 lowercase
// hex characters. A transfer is named by its emitter chain, its emitter in
// hex and its sequence.

// IsRedeemed reports whether a transfer's replay key is recorded.
func IsRedeemed(emitterChain uint16, emitterAddressHex string, sequence uint64) bool {
	key, ok := keyFromHex(emitterChain, emitterAddressHex, sequence)
	return ok && redeemed.Has(key)
}

// Claim returns a transfer's claim: whether it exists, its payload type, its
// recipient, its asset's chain and address, its amount and relayer fee in
// wire units, its body's length and digest, its release time, whether it was
// delayed, and its state: open, completed or cancelled.
func Claim(emitterChain uint16, emitterAddressHex string, sequence uint64) (found bool, payloadID int,
	recipient string, assetChain int, assetAddressHex string, amount, fee int64, bodyLen int, digestHex string,
	releaseTime int64, delayed bool, state string,
) {
	key, ok := keyFromHex(emitterChain, emitterAddressHex, sequence)
	if !ok {
		return
	}
	c := claimAt(key)
	if c == nil {
		return
	}
	states := [...]string{"open", "completed", "cancelled"}
	return true, int(c.payloadID), string(c.recipient), int(c.asset.Chain), hex.EncodeToString(c.asset.Address[:]),
		c.amount, c.fee, c.bodyLen, hex.EncodeToString(c.digest[:]), c.releaseTime, c.delayed, states[c.state]
}

// StagedChunks lists, comma-separated, the indexes of the chunks stager has
// written for a transfer's claim.
func StagedChunks(emitterChain uint16, emitterAddressHex string, sequence uint64, stager address) string {
	key, ok := keyFromHex(emitterChain, emitterAddressHex, sequence)
	s, valid := decodeAddress(stager)
	c := claimAt(key)
	if !ok || !valid || c == nil {
		return ""
	}
	var indexes []string
	for i := 0; i < chunkCount(c.bodyLen); i++ {
		if staged.Has(chunkKey(key, s, i)) {
			indexes = append(indexes, strconv.Itoa(i))
		}
	}
	return strings.Join(indexes, ",")
}

// HasVerifiedBody reports whether a transfer's claim has a verified body, and
// who committed it.
func HasVerifiedBody(emitterChain uint16, emitterAddressHex string, sequence uint64) (bool, string) {
	key, ok := keyFromHex(emitterChain, emitterAddressHex, sequence)
	if !ok {
		return false, ""
	}
	if v := verifiedBodies.Get(key); v != nil {
		return true, string(v.(*verifiedBody).committer)
	}
	return false, ""
}

// GovernanceConsumed reports whether the vault accepted a governance VAA with
// this digest.
func GovernanceConsumed(digestHex string) bool {
	d, ok := hex32(digestHex)
	return ok && consumed.Has(string(d[:]))
}

// WrappedSymbol returns the symbol of the wrapped asset with this origin, or
// "".
func WrappedSymbol(tokenChain uint16, tokenAddressHex string) string {
	a, ok := hex32(tokenAddressHex)
	if !ok {
		return ""
	}
	if w := wrappedAt(tokenbridge.Origin{Chain: tokenChain, Address: a}.Key()); w != nil {
		return w.token.GetSymbol()
	}
	return ""
}

// Origin returns the origin of the wrapped asset with this symbol: its chain
// and its address in hex, and whether it exists.
func Origin(symbol string) (uint16, string, bool) {
	w := wrappedBySymbol(symbol)
	if w == nil {
		return 0, "", false
	}
	return w.origin.Chain, hex.EncodeToString(w.origin.Address[:]), true
}

// AssetMetaDigest returns, in hex, the digest of the AssetMeta that created
// the wrapped token symbol, or "".
func AssetMetaDigest(symbol string) string {
	if w := wrappedBySymbol(symbol); w != nil {
		return hex.EncodeToString(w.meta[:])
	}
	return ""
}

// BalanceOf returns owner's balance of the wrapped token symbol.
func BalanceOf(symbol string, owner address) int64 {
	if w := wrappedBySymbol(symbol); w != nil {
		return w.token.BalanceOf(owner)
	}
	return 0
}

// Allowance returns how much of owner's symbol spender may move.
func Allowance(symbol string, owner, spender address) int64 {
	if w := wrappedBySymbol(symbol); w != nil {
		return w.token.Allowance(owner, spender)
	}
	return 0
}

// TotalSupply returns the wrapped token's supply: the amount of it
// outstanding.
func TotalSupply(symbol string) int64 {
	if w := wrappedBySymbol(symbol); w != nil {
		return w.token.TotalSupply()
	}
	return 0
}

// Peer returns the registered emitter of chainID in hex, or "".
func Peer(chainID uint16) string {
	if e := peers.Get(chainKey(chainID)); e != nil {
		return hex.EncodeToString([]byte(e.(string)))
	}
	return ""
}

// LockedGNOT returns the ugnot held in escrow for transfers out.
func LockedGNOT() int64 {
	return lockedGNOT
}

// PauseState returns whether the bridge is paused, the pause's expiry in
// block-time seconds, and the pauser, freezer and unpauser, "" when
// unassigned.
func PauseState() (bool, int64, string, string, string) {
	return paused, pauseExpiry, string(pauser), string(freezer), string(unpauser)
}

// BoundChainID returns the gno chain ID the bridge is bound to, and any
// pending proposal with its time.
func BoundChainID() (bound, pending string, proposed int64) {
	return boundChainID, pendingChainID, proposedAt
}

// Logic returns the current logic realm's path.
func Logic() string {
	return logic
}

// GNOTMetadata returns the symbol and name GNOT's AssetMeta carries.
func GNOTMetadata() (string, string) {
	return gnotSymbol, gnotName
}

func keyFromHex(emitterChain uint16, emitterHex string, sequence uint64) (string, bool) {
	e, ok := hex32(emitterHex)
	if !ok {
		return "", false
	}
	return tokenbridge.ReplayKey(emitterChain, e, sequence), true
}

func hex32(s string) ([32]byte, bool) {
	var b [32]byte
	d, err := hex.DecodeString(s)
	if err != nil || len(d) != 32 {
		return b, false
	}
	copy(b[:], d)
	return b, true
}

// Render shows the configuration, the state, the peers and the wrapped
// assets. It never echoes path. Names and symbols come from peers'
// AssetMeta, which each token's deployer chose, so they go through
// sanitize.TableCell; strings set outside the vault through
// sanitize.InlineText.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Wormhole token bridge\n\n")
	b.WriteString("- Logic: " + sanitize.InlineText(logic) + "\n")
	b.WriteString("- Chain ID: bound to " + sanitize.InlineText(boundChainID))
	if pendingChainID == "" {
		b.WriteString(" (no pending confirmation)\n")
	} else {
		b.WriteString(" (" + sanitize.InlineText(pendingChainID) + " proposed at " + utc(proposedAt) + ")\n")
	}
	b.WriteString("- Status: " + status() + "\n")
	b.WriteString("- Roles: pauser " + roleText(pauser) + " · freezer " + roleText(freezer) +
		" · unpauser " + roleText(unpauser) + "\n")
	b.WriteString("- Locked GNOT: " + decimal(lockedGNOT, gnotDecimals) + "\n\n")
	b.WriteString("## Peers\n\n")
	if peers.Size() == 0 {
		b.WriteString("No peers registered\n\n")
	} else {
		b.WriteString("| Chain | Emitter |\n|---|---|\n")
		peers.Iterate("", "", func(key string, value any) bool {
			id := int(key[0])<<8 | int(key[1])
			b.WriteString("| " + strconv.Itoa(id) + " | " + hex.EncodeToString([]byte(value.(string))) + " |\n")
			return false
		})
		b.WriteString("\n")
	}
	b.WriteString("## Wrapped assets\n\n")
	if wrapped.Size() == 0 {
		b.WriteString("No wrapped assets\n")
		return b.String()
	}
	b.WriteString("| Symbol | Name | Origin | Decimals | Supply |\n|---|---|---|---|---|\n")
	wrapped.Iterate("", "", func(key string, value any) bool {
		w := value.(*wrappedAsset)
		d := w.token.GetDecimals()
		b.WriteString("| " + sanitize.TableCell(w.token.GetSymbol()) + " | " + sanitize.TableCell(w.token.GetName()) +
			" | " + strconv.Itoa(int(w.origin.Chain)) + ":" + hex.EncodeToString(w.origin.Address[:]) +
			" | " + strconv.Itoa(d) + " | " + decimal(w.token.TotalSupply(), d) + " |\n")
		return false
	})
	return b.String()
}

func status() string {
	var parts []string
	if paused {
		if pauseExpiry == maxInt64 {
			parts = append(parts, "paused until the unpauser lifts it")
		} else {
			parts = append(parts, "paused until "+utc(pauseExpiry))
		}
	}
	if runtime.ChainID() != boundChainID {
		parts = append(parts, "frozen (runtime chain ID differs)")
	}
	if len(parts) == 0 {
		return "running"
	}
	return strings.Join(parts, ", ")
}

func roleText(a address) string {
	if a == "" {
		return "unassigned"
	}
	return string(a)
}

func utc(unix int64) string {
	return time.Unix(unix, 0).UTC().Format(time.RFC3339)
}

// decimal writes a non-negative amount with d decimals.
func decimal(amount int64, d int) string {
	s := strconv.FormatInt(amount, 10)
	if d == 0 {
		return s
	}
	if len(s) <= d {
		s = strings.Repeat("0", d-len(s)+1) + s
	}
	return s[:len(s)-d] + "." + s[len(s)-d:]
}
