// Package tbrecipient is a test-only payload-3 recipient of the token bridge:
// it completes its transfers at the vault's fixed path, so it keeps working
// across logic switches.
package tbrecipient

import "gno.land/r/wormhole/tokenbridge"

// last is the message of the last transfer it completed, converted to bytes in
// this realm.
var last []byte

// Complete completes a transfer to this realm: with its whole body, or with an
// empty one once its operator has staged and committed the body at the vault.
func Complete(cur realm, emitterChain uint16, emitterAddress []byte, sequence uint64, body []byte) {
	last = []byte(tokenbridge.CompletePayload(cross(cur), emitterChain, emitterAddress, sequence, body))
}

// Last returns the message of the last transfer it completed.
func Last() string {
	return string(last)
}
