package core

// The deployment configuration. This committed file fails closed: Wormhole
// chain ID 0 makes init fail with invalid-configuration. The test runner
// replaces it with a test configuration. A deployment replaces it with a
// reviewed configuration that meets every rule the README lists. A
// hand-written file meets only init's checks. Outside gno's test chains,
// those refuse the test chain ID and the corpus's 57 public test keys. They
// do not refuse a replayUntilIndex above the initial set, which strips later
// rotations of their 24 hours; a gno chain ID other than the network's at
// height 0, where init does not compare it; other well-known test keys; or,
// on mainnet, a set other than the published canonical one.
const (
	// wormholeChainID is this chain's Wormhole chain ID, never 0.
	wormholeChainID uint16 = 0
	// gnoChainID is the target network's gno chain ID.
	gnoChainID = ""
	// initialSetIndex and initialKeys are the guardian set installed at
	// deployment; initialKeys packs its 20-byte addresses in index order.
	initialSetIndex uint32 = 0
	initialKeys            = ""
	// replayUntilIndex equals initialSetIndex, except where a deployment
	// replays earlier guardian-set upgrades.
	replayUntilIndex uint32 = 0
)
