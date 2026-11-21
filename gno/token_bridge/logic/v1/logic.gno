// Package logic is the first logic realm of gno's Wormhole token bridge. It
// decides which inbound VAAs the vault pays, whom and when, and which transfers
// go out, under its allowlist and its limits. The vault
// gno.land/r/wormhole/tokenbridge keeps every value and record, and accepts
// these operations only from the current logic, so a logic switch replaces this
// realm's policy and nothing else. A rejection panics with "tokenbridge: "
// followed by the reason code, and every check runs before the first write.
package logic

import (
	"chain/runtime"
	"crypto/bech32"
	"encoding/hex"
	"time"

	"gno.land/p/nt/avl/v0"
	tb "gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/core"
	vault "gno.land/r/wormhole/tokenbridge"
)

// asset is an asset's caps and windows: GNOT's, or a wrapped asset's
// on the allowlist. A new logic starts with empty windows. An exit-only asset
// only goes out: it is neither redeemed nor wrapped.
type asset struct {
	perTransfer   int64
	outboundCap   int64
	inboundBudget int64
	exitOnly      bool
	outbound      window
	inbound       window
}

// assetConfig is a wrapped asset on the configuration's allowlist: its origin,
// its limits in wire units, and whether it is exit-only.
type assetConfig struct {
	tokenChain      uint16
	tokenAddressHex string
	perTransfer     int64
	outboundCap     int64
	inboundBudget   int64
	exitOnly        bool
}

var (
	gnot      *asset
	allowlist avl.Tree // 34-byte origin key → *asset, open or exit-only
)

func init() {
	assets := allowlistConfig()
	reason := checkConfig(gnotPerTransfer, gnotOutboundCap, gnotInboundBudget, assets, core.ChainID())
	if reason != "" {
		panic("tokenbridge: " + reason)
	}
	gnot = &asset{perTransfer: gnotPerTransfer, outboundCap: gnotOutboundCap, inboundBudget: gnotInboundBudget}
	for _, a := range assets {
		token, _ := hex32(a.tokenAddressHex)
		allowlist.Set(tb.Origin{Chain: a.tokenChain, Address: token}.Key(), &asset{perTransfer: a.perTransfer,
			outboundCap: a.outboundCap, inboundBudget: a.inboundBudget, exitOnly: a.exitOnly})
	}
}

// checkConfig applies init's checks to a configuration, on Wormhole chain
// self, and returns why it fails, or "". A limit is never negative, an
// exit-only entry's included. An entry, open or exit-only, names a 32-byte
// address on another chain that a peer could have, once, so no asset is both.
func checkConfig(perTransfer, outboundCap, inboundBudget int64, assets []assetConfig, self uint16) string {
	if perTransfer < 0 || outboundCap < 0 || inboundBudget < 0 {
		return "invalid-configuration"
	}
	seen := map[string]bool{}
	for _, a := range assets {
		token, ok := hex32(a.tokenAddressHex)
		if !ok || a.tokenChain == 0 || a.tokenChain == self ||
			a.perTransfer < 0 || a.outboundCap < 0 || a.inboundBudget < 0 {
			return "invalid-configuration"
		}
		key := tb.Origin{Chain: a.tokenChain, Address: token}.Key()
		if seen[key] {
			return "invalid-configuration"
		}
		seen[key] = true
	}
	return ""
}

// Activate presents an action-2 VAA naming this realm to the vault's Upgrade,
// which sees this realm as its caller. Anyone may call it. It applies
// no gate, so a switch can land while paused, and Upgrade refuses it under the
// chain-ID freeze.
func Activate(cur realm, raw []byte) {
	vault.Upgrade(cross(cur), raw)
}

// gate applies the vault's value gate through its reads: the bridge is
// not paused, and not under the chain-ID freeze.
func gate() {
	if paused, _, _, _, _ := vault.PauseState(); paused {
		panic("tokenbridge: bridge-paused")
	}
	if bound, _, _ := vault.BoundChainID(); runtime.ChainID() != bound {
		panic("tokenbridge: bridge-frozen")
	}
}

// blockTime is the block time in seconds, never negative.
func blockTime() int64 {
	if t := time.Now().Unix(); t > 0 {
		return t
	}
	return 0
}

// assetOf returns GNOT's limits for GNOT's origin, or a wrapped asset's on the
// allowlist, open or exit-only, or nil.
func assetOf(o tb.Origin) *asset {
	if o.Chain == core.ChainID() && o.Address == tb.GNOTAddress() {
		return gnot
	}
	if a := allowlist.Get(o.Key()); a != nil {
		return a.(*asset)
	}
	return nil
}

// openAsset returns an asset that may come in, by redemption or wrapping: GNOT,
// or an open entry of the allowlist. An exit-only or unlisted wrapped asset
// fails with not-allowlisted.
func openAsset(o tb.Origin) *asset {
	a := assetOf(o)
	if a == nil || a.exitOnly {
		panic("tokenbridge: not-allowlisted")
	}
	return a
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

// encodeAddress returns 20 bytes as a gno address.
func encodeAddress(b []byte) address {
	s, err := bech32.EncodeFromBase256("g", b)
	if err != nil {
		panic(err) // 20 bytes always encode
	}
	return address(s)
}

// fail panics with a package error's reason code.
func fail(err error) {
	if err != nil {
		panic("tokenbridge: " + err.Error())
	}
}
