// PKGPATH: gno.land/r/wormhole_test/caller
package caller

// cross refuses a realm value that is not the current one: here this realm's
// cur, captured by a function the relay runs while it is the current realm. So
// the relay cannot publish under this realm's emitter through it. The refusal
// is a VM error, which revive does not catch: it aborts the whole transaction,
// so nothing is published. z_publish_no_cross pins the other way, a call
// without cross.

import (
	"gno.land/r/wormhole/core"
	"gno.land/r/wormhole_test/relay"
)

func main(cur realm) {
	relay.Run(cross(cur), func() {
		core.PublishMessage(cross(cur), 0, nil, 1)
	})
}

// Error:
// cross: rlm is not the current cur (stale capture or sibling frame)
