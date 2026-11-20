// PKGPATH: gno.land/r/wormhole_test/logicinit
package logicinit

// The state init seeds from the configuration, on a fresh store:
// GNOT and the corpus's allowlisted asset, each with limits that do not bind
// and empty windows. Any other asset has none, and a read that cannot decode
// its argument returns zero values. Render shows the same, and never echoes
// its path.

import (
	"encoding/hex"

	tb "gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/tokenbridge/logic/v1"
)

const usdc = "000000000000000000000000a000000000000000000000000000000000000048"

func main() {
	token := tb.GNOTAddress()
	gnot := hex.EncodeToString(token[:])
	println(logic.Allowlisted(65535, gnot), logic.Allowlisted(2, usdc), logic.Allowlisted(4, usdc), logic.Allowlisted(2, "zz"))
	println(logic.Limits(65535, gnot))
	println(logic.Limits(2, usdc))
	println(logic.Limits(4, usdc))
	println(logic.Limits(2, "zz"))
	println(logic.Render("[x](javascript:alert(1))"))
}

// Output:
// true true false false
// true 9223372036854775807 9223372036854775807 0 9223372036854775807 0
// true 9223372036854775807 9223372036854775807 0 9223372036854775807 0
// false 0 0 0 0 0
// false 0 0 0 0 0
// # Token bridge logic v1
//
// Vault: gno.land/r/wormhole/tokenbridge
//
// GNOT in GNOT, other assets in wire units.
//
// | Asset | Status | Outbound per transfer | Outbound 24 h (used / cap) | Inbound 24 h (used / budget) |
// |---|---|---|---|---|
// | GNOT | open | 9223372036854.775807 | 0.000000 / 9223372036854.775807 | 0.000000 / 9223372036854.775807 |
// | 2:000000000000000000000000a000000000000000000000000000000000000048 | open | 9223372036854775807 | 0 / 9223372036854775807 | 0 / 9223372036854775807 |
