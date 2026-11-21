// PKGPATH: gno.land/r/wormhole_test/reader
package reader

// init installs the configuration's set as current, with no expiry, and the
// message fee starts at 0. The test runner's configuration is the corpus's
// set 3 under Wormhole chain ID 65535, on gno test's chain ID, dev.

import (
	"strconv"

	"gno.land/r/wormhole/core"
)

func main() {
	keys, expiration, expired, ok := core.GuardianSet(3)
	println(len(keys)/20, expiration, expired, ok)
	_, _, _, ok = core.GuardianSet(4)
	println(ok)
	println(core.CurrentGuardianSetIndex(), core.ChainID(), core.GnoChainID(), core.MessageFee())
	println(strconv.Quote(core.Render("")))
}

// Output:
// 19 0 false true
// false
// 3 65535 dev 0
// "# Wormhole Core\n\n- Wormhole chain ID: 65535\n- Gno chain ID: dev\n- Current guardian set: 3, 19 guardians\n- Message fee: 0 ugnot\n"
