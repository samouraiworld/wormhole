// Package allocator is a test-only realm that hands out buffers it owns, as a
// relayer realm passing a VAA on would. The test runner copies it into
// the test workspace; it is never deployed.
package allocator

// Copy returns a copy of b. It is not crossing, so the copy is allocated
// while this realm is the storage realm, and belongs to it.
func Copy(b []byte) []byte {
	return append([]byte(nil), b...)
}
