// PKGPATH: gno.land/r/wormhole_test/publisher
package publisher

// PublishMessage takes the emitter from its caller: this realm, a sub-realm
// it mints, or a user. Each prints its sequence, the next one, and its
// address's 20 bytes, which the event's emitter must carry left-padded to 32.
// The events pin schema v1.

import (
	"crypto/bech32"
	"encoding/hex"
	"testing"

	"gno.land/r/wormhole/core"
)

func publish(cur realm, from address, nonce uint32, payload string, consistency uint8) {
	_, b, err := bech32.DecodeToBase256(string(from))
	if err != nil {
		panic(err)
	}
	var emitter [32]byte
	copy(emitter[12:], b)
	seq := core.PublishMessage(cross(cur), nonce, []byte(payload), consistency)
	println(seq, core.NextSequence(emitter), hex.EncodeToString(b))
}

func main(cur realm) {
	publish(cur, cur.Address(), 7, "realm", 1)
	publish(cur, cur.Address(), 8, "", 200)
	sub := cur.Sub("relay")
	_, b, _ := bech32.DecodeToBase256(string(sub.Address()))
	var subEmitter [32]byte
	copy(subEmitter[12:], b)
	println(sub.PkgPath(), core.PublishMessage(cross(sub), 4294967295, []byte("sub"), 15), core.NextSequence(subEmitter), hex.EncodeToString(b))
	user := address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	testing.SetRealm(testing.NewUserRealm(user))
	publish(cur, user, 0, "\x00\xff", 0)
}

// Output:
// 0 1 2c25fa2a72122c210db098d1b953440de4af1487
// 1 2 2c25fa2a72122c210db098d1b953440de4af1487
// gno.land/r/wormhole_test/publisher#relay 0 1 934c504b9eb55caa663b3610668dec612337aee9
// 0 1 920fb5f17c2daf74bb1599b7cbe0295a5e1ec9b7

// Events:
// [
//   {
//     "type": "WormholeMessage",
//     "attrs": [
//       {
//         "key": "emitter",
//         "value": "0000000000000000000000002c25fa2a72122c210db098d1b953440de4af1487"
//       },
//       {
//         "key": "sequence",
//         "value": "0"
//       },
//       {
//         "key": "nonce",
//         "value": "7"
//       },
//       {
//         "key": "consistency",
//         "value": "1"
//       },
//       {
//         "key": "payload",
//         "value": "7265616c6d"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/core"
//   },
//   {
//     "type": "WormholeMessage",
//     "attrs": [
//       {
//         "key": "emitter",
//         "value": "0000000000000000000000002c25fa2a72122c210db098d1b953440de4af1487"
//       },
//       {
//         "key": "sequence",
//         "value": "1"
//       },
//       {
//         "key": "nonce",
//         "value": "8"
//       },
//       {
//         "key": "consistency",
//         "value": "200"
//       },
//       {
//         "key": "payload",
//         "value": ""
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/core"
//   },
//   {
//     "type": "WormholeMessage",
//     "attrs": [
//       {
//         "key": "emitter",
//         "value": "000000000000000000000000934c504b9eb55caa663b3610668dec612337aee9"
//       },
//       {
//         "key": "sequence",
//         "value": "0"
//       },
//       {
//         "key": "nonce",
//         "value": "4294967295"
//       },
//       {
//         "key": "consistency",
//         "value": "15"
//       },
//       {
//         "key": "payload",
//         "value": "737562"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/core"
//   },
//   {
//     "type": "WormholeMessage",
//     "attrs": [
//       {
//         "key": "emitter",
//         "value": "000000000000000000000000920fb5f17c2daf74bb1599b7cbe0295a5e1ec9b7"
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
//         "value": "0"
//       },
//       {
//         "key": "payload",
//         "value": "00ff"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/core"
//   }
// ]
