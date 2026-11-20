// Package holder is a test-only realm that keeps a buffer and can rewrite it,
// as a relayer realm holding a VAA for consumers could. The test runner
// copies it into the test workspace; it is never deployed.
package holder

var raw []byte

// Store keeps a copy of b, allocated by this realm.
func Store(cur realm, b []byte) {
	raw = append([]byte(nil), b...)
}

// Raw returns the kept buffer itself, not a copy.
func Raw() []byte {
	return raw
}

// Rewrite flips the case of the kept buffer's last byte.
func Rewrite(cur realm) {
	raw[len(raw)-1] ^= 0x20
}
