package tokenbridge

// The deployment configuration. This committed file fails closed: Wormhole
// chain ID 0 makes init fail with invalid-configuration. The test runner
// replaces it with a test configuration, and a deployment with a reviewed
// configuration that meets every rule the README lists. A hand-written file
// meets only init's checks.
const (
	// wormholeChainID and gnoChainID must equal Core's.
	wormholeChainID uint16 = 0
	gnoChainID             = ""
	// initialLogic is the first logic realm's path.
	initialLogic = "gno.land/r/wormhole/tokenbridge/logic/v1"
	// gnotSymbol and gnotName are the strings GNOT's AssetMeta carries,
	// which peers keep for good.
	gnotSymbol = "GNOT"
	gnotName   = "Gno.land"
)
