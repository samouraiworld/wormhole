// PKGPATH: gno.land/r/wormhole_test/claimevents
package claimevents

// The claim operations' events, schema v1, each
// from one call on a fresh vault: TransferRedeemed for MarkRedeemed;
// TransferRedeemed, then ClaimRecorded, for RecordClaim; ClaimCompleted for
// CompleteClaim and for CompletePayload; ClaimCancelled for CancelClaim. The
// claims pay nothing, so no bank event comes between.

import (
	"chain"
	"crypto/keccak256"
	"encoding/hex"
	"testing"
	"time"

	tb "gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/tokenbridge"
)

const (
	start     = 1_800_000_000
	logic     = "gno.land/r/wormhole/tokenbridge/logic/v1"
	recipient = "gno.land/r/wormhole_test/tbrecipient"
)

func wire(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return b
}

// claim is a GNOT claim of nothing for body.
func claim(id uint8, to address, release int64, body []byte) tb.Claim {
	h := keccak256.Sum256(body)
	return tb.Claim{Digest: keccak256.Sum256(h[:]), PayloadID: id, Recipient: to,
		Asset: tb.Origin{Chain: 65535, Address: tb.GNOTAddress()}, BodyLen: len(body), ReleaseTime: release}
}

func main(cur realm) {
	ctx := testing.GetContext()
	ctx.Time = time.Unix(start, 0)
	testing.SetContext(ctx)
	user := chain.PackageAddress("gno.land/r/wormhole_test/user")
	emitter := [32]byte{31: 0xee}
	body := make([]byte, 51+133)
	testing.SetRealm(testing.NewCodeRealm(logic))
	tokenbridge.MarkRedeemed(cross(cur), 2, emitter, 1)
	tokenbridge.RecordClaim(cross(cur), 2, emitter, 2, claim(1, user, start, body))
	tokenbridge.CompleteClaim(cross(cur), 2, emitter, 2, body, user)
	tokenbridge.RecordClaim(cross(cur), 2, emitter, 3, claim(3, chain.PackageAddress(recipient), start, body))
	tokenbridge.RecordClaim(cross(cur), 2, emitter, 4, claim(1, user, start+86400, body))
	tokenbridge.SetPauserAddresses(cross(cur), wire("01000000030d00dbf41ee2ae64f7a02643822a4a22558b80044bd48df8657fb85131ae1e7a292872ddef95fb4de8da74a33540780ab0efad78a2753019aa19d92e85fb055422a600010c4dd71f4b51870cc654c4bf4e415694612218e2732652fef78eb694b20bc6a614f305d25a0a25bd1ba914ff106e3d8555fed844683b12c0f9a9b466bd0e57370102c03865e07a9c2c4203d81b796e3f3bb3cf515e304fd81dc746dc72e96b38f94b1c6b275d8bf238af3e8bde44f6dca4d53783eb15abbbef1333dec877d414b3c1010386cabda02ac06819ed6d187aa71351871f749f9b8e5c611af8c83260858cea003313bd0c9187399683ffc4fdd124c619fd14f7c211549364a6a191573f580bc00004c30c7b57fb4009ba8bf6e483f00607c52601a1be91547b775bf775f1e039c7682eddb012b0b5c00010549e6a25eccbbca1700a0ea4557fe804d326cb3586df5600052b9c6fd67fe9c4490079832d93f05d0d73f0b7721ed78678fdea4fa0c4e1589a231284776fde3ee138193f13f2f274442fbfc43b8b5111a419deda58fcb3786400061a7a967d33f6c0c0636f5e11479c737aa01d2343d58e833101ee8d77174c1a251822ac18be715d328238642be3582ba3bd4cfab5ed86450c4c45ce3f6a8b0c2e01074e483d7b0cdd2b85e90eac30deec72ed8770f00f692571e326252d706bef84317c8d5182106e540e3159b4a860e42737d496e904c435f6eb37f8d22af9f8936f0008fb5ce93583cb808bdd7d3c7a0ad72daa74b78790af89436667d5c545fce14b8e4b82cd41ecc72b1bfea579ac21b8f795e87792afd06cdbe28fedbb25c0fe1b0c010972ff7b66fa8775b92f5a2480d62c78a9efadb50b643c8bcd350845428d18800919976ba39fffa013e03b1749cfe84c337129674d49ed2168d21292f6006dba25010aa542a6260dc12c00691b01cd9e919c440939dc982cd68039d01a4b6dfdf411b036db88871c3a9bc96963ad5e17b6c671b33dd9ff83cc5815ad6c814c3b841219000bbbd5c9502000f7abd0699b2657fe6bc4dcbdff65a63b864ee281ddc4749aa69b014fa4a25622d895ba5edd5ef8a83472efe7ca609acba846fa7fdef515bae3d2010cb5523ff8be57d0d7e75c3334d416c53bd3588897968f9de4d3307a2acd6da19c0c26ebfdd6f13ca59406131a45eaec015b07d989a6eb89a4e25bbe8371dc7f8a016b49d200000000070001000000000000000000000000000000000000000000000000000000000000000400000000000000d601000000000000000000000000000000000000000000546f6b656e42726964676504ffff14514845a71a60dad8be03ba0cfab4f7a66d4b4c4714535a4d9144fbf9a2c490f9b68f63595781fee564146e741991ca9547c4d82d3e348340a6f17d369ee0"))
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/pauser"))
	tokenbridge.Pause(cross(cur))
	testing.SetRealm(testing.NewCodeRealm(logic))
	tokenbridge.CancelClaim(cross(cur), 2, emitter, 4)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/unpauser"))
	tokenbridge.Unpause(cross(cur))
	testing.SetRealm(testing.NewCodeRealm(recipient))
	println(len(tokenbridge.CompletePayload(cross(cur), 2, emitter[:], 3, body)))
}

// Output:
// 133

// Events:
// [
//   {
//     "type": "TransferRedeemed",
//     "attrs": [
//       {
//         "key": "emitter_chain",
//         "value": "2"
//       },
//       {
//         "key": "emitter_address",
//         "value": "00000000000000000000000000000000000000000000000000000000000000ee"
//       },
//       {
//         "key": "sequence",
//         "value": "1"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "TransferRedeemed",
//     "attrs": [
//       {
//         "key": "emitter_chain",
//         "value": "2"
//       },
//       {
//         "key": "emitter_address",
//         "value": "00000000000000000000000000000000000000000000000000000000000000ee"
//       },
//       {
//         "key": "sequence",
//         "value": "2"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ClaimRecorded",
//     "attrs": [
//       {
//         "key": "emitter_chain",
//         "value": "2"
//       },
//       {
//         "key": "emitter_address",
//         "value": "00000000000000000000000000000000000000000000000000000000000000ee"
//       },
//       {
//         "key": "sequence",
//         "value": "2"
//       },
//       {
//         "key": "release_time",
//         "value": "1800000000"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ClaimCompleted",
//     "attrs": [
//       {
//         "key": "emitter_chain",
//         "value": "2"
//       },
//       {
//         "key": "emitter_address",
//         "value": "00000000000000000000000000000000000000000000000000000000000000ee"
//       },
//       {
//         "key": "sequence",
//         "value": "2"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "TransferRedeemed",
//     "attrs": [
//       {
//         "key": "emitter_chain",
//         "value": "2"
//       },
//       {
//         "key": "emitter_address",
//         "value": "00000000000000000000000000000000000000000000000000000000000000ee"
//       },
//       {
//         "key": "sequence",
//         "value": "3"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ClaimRecorded",
//     "attrs": [
//       {
//         "key": "emitter_chain",
//         "value": "2"
//       },
//       {
//         "key": "emitter_address",
//         "value": "00000000000000000000000000000000000000000000000000000000000000ee"
//       },
//       {
//         "key": "sequence",
//         "value": "3"
//       },
//       {
//         "key": "release_time",
//         "value": "1800000000"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "TransferRedeemed",
//     "attrs": [
//       {
//         "key": "emitter_chain",
//         "value": "2"
//       },
//       {
//         "key": "emitter_address",
//         "value": "00000000000000000000000000000000000000000000000000000000000000ee"
//       },
//       {
//         "key": "sequence",
//         "value": "4"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ClaimRecorded",
//     "attrs": [
//       {
//         "key": "emitter_chain",
//         "value": "2"
//       },
//       {
//         "key": "emitter_address",
//         "value": "00000000000000000000000000000000000000000000000000000000000000ee"
//       },
//       {
//         "key": "sequence",
//         "value": "4"
//       },
//       {
//         "key": "release_time",
//         "value": "1800086400"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "PauserAddressesSet",
//     "attrs": [
//       {
//         "key": "pauser",
//         "value": "g129yytfc6vrdd30srhgx04d8h5ek5knz8sgeh2j"
//       },
//       {
//         "key": "freezer",
//         "value": "g12ddymy2yl0u693yslxmg7c6e27qlaety5mmmrr"
//       },
//       {
//         "key": "unpauser",
//         "value": "g1de6pnyw2j4rufkpd8c6gxs9x797nd8hqfstsgy"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "Paused",
//     "attrs": [
//       {
//         "key": "by",
//         "value": "g129yytfc6vrdd30srhgx04d8h5ek5knz8sgeh2j"
//       },
//       {
//         "key": "expiry",
//         "value": "1800432000"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ClaimCancelled",
//     "attrs": [
//       {
//         "key": "emitter_chain",
//         "value": "2"
//       },
//       {
//         "key": "emitter_address",
//         "value": "00000000000000000000000000000000000000000000000000000000000000ee"
//       },
//       {
//         "key": "sequence",
//         "value": "4"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "Unpaused",
//     "attrs": [
//       {
//         "key": "by",
//         "value": "g1de6pnyw2j4rufkpd8c6gxs9x797nd8hqfstsgy"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ClaimCompleted",
//     "attrs": [
//       {
//         "key": "emitter_chain",
//         "value": "2"
//       },
//       {
//         "key": "emitter_address",
//         "value": "00000000000000000000000000000000000000000000000000000000000000ee"
//       },
//       {
//         "key": "sequence",
//         "value": "3"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   }
// ]
