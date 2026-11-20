// Package relay is a test-only realm that publishes through Core for its
// callers, as a bridge realm other realms call would, and runs a caller's
// function while it is the current realm. The test runner copies it
// into the test workspace; it is never deployed.
package relay

import "gno.land/r/wormhole/core"

// Relay publishes payload as this realm, whoever calls it.
func Relay(cur realm, payload string) uint64 {
	return core.PublishMessage(cross(cur), 0, []byte(payload), 1)
}

// Run calls fn while this realm is the current realm.
func Run(cur realm, fn func()) {
	fn()
}
