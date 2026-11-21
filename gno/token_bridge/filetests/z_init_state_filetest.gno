// PKGPATH: gno.land/r/wormhole_test/initstate
package initstate

// The state init leaves, on a fresh store under the test configuration: the
// configured first logic, bound to the configured gno chain ID with nothing
// pending, not paused and with no pause role, nothing locked, no peer, no
// wrapped asset, and GNOT's configured AssetMeta strings.

import "gno.land/r/wormhole/tokenbridge"

func main() {
	println(tokenbridge.Logic())
	bound, pending, proposed := tokenbridge.BoundChainID()
	println(bound, pending == "", proposed)
	paused, expiry, pauser, freezer, unpauser := tokenbridge.PauseState()
	println(paused, expiry, pauser == "", freezer == "", unpauser == "")
	_, _, wrappedGNOT := tokenbridge.Origin("GNOT")
	println(tokenbridge.LockedGNOT(), tokenbridge.Peer(2) == "", wrappedGNOT)
	println(tokenbridge.GNOTMetadata())
}

// Output:
// gno.land/r/wormhole/tokenbridge/logic/v1
// dev true 0
// false 0 true true true
// 0 true false
// GNOT Gno.land
