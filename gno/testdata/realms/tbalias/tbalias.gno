// Package tbalias is a test-only realm that exports the logic's TransferGNOT
// under its own name. A MsgCall to X names this realm, not the logic, so on a
// node the logic's origin-call guard refuses it, since gno compares the
// message's path. The filetests call X from a realm, which is no user call
// at all.
package tbalias

import logic "gno.land/r/wormhole/tokenbridge/logic/v1"

// X is the logic's TransferGNOT.
var X = logic.TransferGNOT
