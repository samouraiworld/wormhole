// PKGPATH: gno.land/r/wormhole_test/caller
package caller

// A realm publishing through another realm, as with a bridge realm other
// realms call: the emitter is the realm that calls Core, the relay, not
// this caller nor the user who signed the transaction. The events carry
// the relay's address.

import (
	"chain"
	"crypto/bech32"
	"encoding/hex"
	"testing"

	"gno.land/r/wormhole/core"
	"gno.land/r/wormhole_test/relay"
)

func emitter(a address) [32]byte {
	_, b, err := bech32.DecodeToBase256(string(a))
	if err != nil {
		panic(err)
	}
	var e [32]byte
	copy(e[12:], b)
	return e
}

func main(cur realm) {
	relayEmitter := emitter(chain.PackageAddress("gno.land/r/wormhole_test/relay"))
	println(relay.Relay(cross(cur), "x"), relay.Relay(cross(cur), "y"), hex.EncodeToString(relayEmitter[12:]))
	println(core.NextSequence(relayEmitter), core.NextSequence(emitter(cur.Address())),
		core.NextSequence(emitter(testing.GetContext().OriginCaller)))
}

// Output:
// 0 1 3e017662e2c5f833779025bf5e385781a3b5b48c
// 2 0 0

// Events:
// [
//   {
//     "type": "WormholeMessage",
//     "attrs": [
//       {
//         "key": "emitter",
//         "value": "0000000000000000000000003e017662e2c5f833779025bf5e385781a3b5b48c"
//       },
//       {
//         "key": "sequence",
//         "value": "0"
//       },
//       {
//         "key": "nonce",
//         "value": "0"
//       },
//       {
//         "key": "consistency",
//         "value": "1"
//       },
//       {
//         "key": "payload",
//         "value": "78"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/core"
//   },
//   {
//     "type": "WormholeMessage",
//     "attrs": [
//       {
//         "key": "emitter",
//         "value": "0000000000000000000000003e017662e2c5f833779025bf5e385781a3b5b48c"
//       },
//       {
//         "key": "sequence",
//         "value": "1"
//       },
//       {
//         "key": "nonce",
//         "value": "0"
//       },
//       {
//         "key": "consistency",
//         "value": "1"
//       },
//       {
//         "key": "payload",
//         "value": "79"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/core"
//   }
// ]
