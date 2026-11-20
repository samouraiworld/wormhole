// PKGPATH: gno.land/r/wormhole_test/caller
package caller

// PublishMessage takes its emitter from cur.Previous(), so another realm
// could take an emitter only by handing Core a realm value cross did not
// make. gno refuses a call that passes this realm's cur without cross
// before anything runs. z_publish_stale_realm pins
// the other way, cross on a realm value that is not current.

import "gno.land/r/wormhole/core"

func main(cur realm) {
	core.PublishMessage(cur, 0, nil, 1)
}

// Error:
// gno.land/r/wormhole_test/caller/z_publish_no_cross.gno:13:2-37: cannot cur-call to external realm function gno.land/r/wormhole/core.core<VPBlock(2,0)>.PublishMessage from gno.land/r/wormhole_test/caller
