// PKGPATH: gno.land/r/wormhole_test/naming
package naming

// Wrapped-token naming on a fresh vault: an Ethereum token with 18
// decimals wraps with 8, its own symbol and its name with " (Wormhole)", and
// is registered in grc20reg under the vault's path and its symbol. A repeat
// fails with wrapped-exists. A second token with the same symbol becomes WH1,
// and a symbol grc20 refuses becomes WH2. Render shows a hostile name inert:
// no link, no table break.

import (
	"testing"

	tb "gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/nt/grc20reg/v0"
	"gno.land/r/wormhole/tokenbridge"
)

func asset(chain uint16, last byte, decimals uint8, symbol, name string) tb.AssetMeta {
	m := tb.AssetMeta{Token: tb.Origin{Chain: chain, Address: [32]byte{31: last}}, Decimals: decimals}
	copy(m.Symbol[:], symbol)
	copy(m.Name[:], name)
	return m
}

func main(cur realm) {
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole/tokenbridge/logic/v1"))
	weth := asset(2, 1, 18, "WETH", "Wrapped Ether")
	tokenbridge.CreateWrapped(cross(cur), weth, [32]byte{})
	token := grc20reg.Get("gno.land/r/wormhole/tokenbridge.WETH")
	println(token.GetSymbol(), token.GetName(), token.GetDecimals())
	println(revive(func() { tokenbridge.CreateWrapped(cross(cur), weth, [32]byte{}) }))
	tokenbridge.CreateWrapped(cross(cur), asset(4, 2, 18, "WETH", "Wrapped Ether"), [32]byte{})
	println(tokenbridge.WrappedSymbol(4, "0000000000000000000000000000000000000000000000000000000000000002"))
	tokenbridge.CreateWrapped(cross(cur), asset(2, 3, 6, "U|SD", "](javascript:alert(1))|x"), [32]byte{})
	println(tokenbridge.WrappedSymbol(2, "0000000000000000000000000000000000000000000000000000000000000003"))
	println(tokenbridge.Render("ignored/path"))
}

// Output:
// WETH Wrapped Ether (Wormhole) 8
// tokenbridge: wrapped-exists
// WH1
// WH2
// # Wormhole token bridge
//
// - Logic: gno\.land/r/wormhole/tokenbridge/logic/v1
// - Chain ID: bound to dev (no pending confirmation)
// - Status: running
// - Roles: pauser unassigned · freezer unassigned · unpauser unassigned
// - Locked GNOT: 0.000000
//
// ## Peers
//
// No peers registered
//
// ## Wrapped assets
//
// | Symbol | Name | Origin | Decimals | Supply |
// |---|---|---|---|---|
// | WETH | Wrapped Ether \(Wormhole\) | 2:0000000000000000000000000000000000000000000000000000000000000001 | 8 | 0.00000000 |
// | WH2 | \]\(javascript:alert\(1\)\)\|x \(Wormhole\) | 2:0000000000000000000000000000000000000000000000000000000000000003 | 6 | 0.000000 |
// | WH1 | Wrapped Ether \(Wormhole\) | 4:0000000000000000000000000000000000000000000000000000000000000002 | 8 | 0.00000000 |
