package tokenbridge

import (
	"encoding/hex"
	"strconv"
)

// Wrapped-token naming. A wrapper's name and symbol are
// derived from its AssetMeta, so that no AssetMeta can fail wrapped creation
// through its strings. The checks are grc20's own (p/nt/grc20/v0/token.gno,
// validName and validSymbol): a name or symbol they accept never makes
// grc20.NewToken panic.

const (
	maxNameLen   = 64 // grc20.MaxNameLen
	maxSymbolLen = 11 // grc20.MaxSymbolLen
)

// String32 reads a 32-byte AssetMeta string up to its first zero byte, as
// EVM's bytes32ToString does (ethereum/contracts/bridge/Bridge.sol).
func String32(b [32]byte) string {
	for i, c := range b {
		if c == 0 {
			return string(b[:i])
		}
	}
	return string(b[:])
}

// Pad32 returns s zero-padded to 32 bytes, as GNOT's AssetMeta carries its
// configured symbol and name. It reports false unless s has 1 to 32 bytes and
// no zero byte: EVM reads such a string up to its first zero byte, and Solana
// and CosmWasm drop every zero byte, so peers would read it differently.
func Pad32(s string) ([32]byte, bool) {
	var b [32]byte
	if len(s) == 0 || len(s) > 32 {
		return b, false
	}
	for i := 0; i < len(s); i++ {
		if s[i] == 0 {
			return b, false
		}
	}
	copy(b[:], s)
	return b, true
}

// ValidName reports whether grc20 accepts s as a token name: 1 to 64 bytes,
// no rune below 0x20 and no 0x7f.
func ValidName(s string) bool {
	if s == "" || len(s) > maxNameLen {
		return false
	}
	for _, c := range s {
		if c < 0x20 || c == 0x7f {
			return false
		}
	}
	return true
}

// ValidSymbol reports whether grc20 accepts s as a token symbol: 1 to 11
// bytes, each in [A-Za-z0-9_-].
func ValidSymbol(s string) bool {
	if s == "" || len(s) > maxSymbolLen {
		return false
	}
	for _, c := range s {
		alnum := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
		if !alnum && c != '_' && c != '-' {
			return false
		}
	}
	return true
}

// WrappedName returns the name of m's wrapper: m's name followed by
// " (Wormhole)" if grc20 accepts that, and otherwise "Wormhole <chain>:<hex>",
// the token chain in decimal and the last 20 bytes of its address in hex, at
// most 55 bytes.
func WrappedName(m AssetMeta) string {
	if name := String32(m.Name) + " (Wormhole)"; ValidName(name) {
		return name
	}
	return "Wormhole " + strconv.Itoa(int(m.Token.Chain)) + ":" + hex.EncodeToString(m.Token.Address[12:])
}

// FallbackSymbol returns the n-th symbol the vault tries when an AssetMeta's
// own symbol is invalid or taken: WH1, WH2, and so on.
func FallbackSymbol(n int) string { return "WH" + strconv.Itoa(n) }
