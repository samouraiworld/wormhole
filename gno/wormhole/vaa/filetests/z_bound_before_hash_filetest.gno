package main

// A VAA 500,001 payload bytes long under a 500,000-byte bound is malformed
// before its body is hashed: hashing it first would raise the exact gas
// below, and the test would fail. The figure moves with any change to
// vaa.gno or to this file; gno test -update-golden-tests rewrites it.

import "gno.land/p/wormhole/vaa/v0"

func main() {
	raw := make([]byte, 6+66*13+51+500_001)
	raw[0] = 1
	raw[5] = 13
	_, err := vaa.Verify(raw, string(make([]byte, 19*20)), 500_000)
	println(err.Error())
}

// Output:
// malformed

// Gas:
// 177207
