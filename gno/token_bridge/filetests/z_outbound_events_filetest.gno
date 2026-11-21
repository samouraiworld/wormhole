// PKGPATH: gno.land/r/wormhole_test/outbound
package outbound

// The outbound operations publish what the same call locks or burns:
// payload 1 or 3 for exactly that amount, from the vault's emitter, and
// WormholeTransferOut from the same values; GNOT's AssetMeta comes from the
// configuration, with no event. Each of the five operations runs once, so the
// events pin schema v1 and every payload's bytes:
// GNOT's or the asset's origin, the amount, the recipient and its
// chain, then the fee or the sender's 20 bytes, left-padded, and the payload.

import (
	"chain"
	"encoding/hex"
	"testing"

	tb "gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/tokenbridge"
)

func main(cur realm) {
	// Corpus step: RegisterChain for chain 2, presented by anyone.
	raw, err := hex.DecodeString("01000000030d000245f1b6fd6d2a5cf77015fe989b78a92c54f5dd086b20ba9bd5078dfa20507c5b34daecd1ac129d9d59cec27cd91dc67901911a6f96fcfca0a7f71cdf00ab8b00010fe52569de6755691d8275e5a053442b37bedbdc26383196617781762156d8524d1f45154949c43170eef302ccd5a65043a4c84814e696c285e50fb30f0d1f78000211f09cb4bdafbc9eb299c03df07fa38791e83a3f369aebafceec05351de76c087651984e77c3f39a35e971e219f4f4f681b94d242f2db000189c4ebd5a4e893a0103c4cc5156263a5da8c54f6768373f7de41d73177082cf5736d4e36b7b8f0a3f153c6af0022b6d53bbbb5aec57324f9ad12be5dddd63c0547a4b422dda2f7c9a8e0004d5329bc3204c9986c649d0bda12409730e55d7af0241666733b35465e35df02e05dcd0c11e47733ff0d2a750e38a24505ad8347eecc12d956c0b4fa5c3c5b3000105795717059344c813633fa85d0300d190906cc700c73ff538d810110c551f0a2d7cec9052d1a0e2489b5b38cbfbf20f6448adcdf5b79aec452f5c65d37d18128801064765df7ce01424e9b2a8d2d2ccdfeeb582d93742835ffde8f5674693871371303aa1c7abcc30848cdd9189731b14e25c7084324fa624c02dd71b7c8384460ecb0107da264205502aeb83dd264f0632dfd0f6d11f1fc2e96f032fb7b542748a9df11c18c8d3272249583f93d07c46dbe371741ae0dd4b82f890e3110e9dac564ad5ba0008a8bfe6e2d4902c80b745cf4c67ea2b811f0f634412a5c4fb8baa176caf9e8cd40eb38ae6459e80e389e64ccf6385c492e1ab30970688a8ffce754d85719635ae0109204806cab5e947e5508f2f7fce88dc1d10f58b5ff96033cc92676a58e0cc5b0b44ba35d0bf259da0592043ea0485925935b6f36607fde363f127edf64c624755000af9cd3116bca268f97db66e3cac4d7d4e976d5f497ba1fee25bc877d4f6d395507da92f87bed17ad240396f7f4ca6f5d5f27387149be9794a147aef626732cc8a010b4a75d8592eadb68ab48dba07a1ccbf8750a61dda96b10f6a8dc74f88fcb529b227fb110568b1fb91a77e93274e0846dad2501a1cfef1565caf65417bf4f6db44010c3b12e826a8be1b37ec530f7b23c473b8d66b6e1a59f55c3d3f66aca90aa6ffe36511e78f53f06be21bd3925a53701b261a432cb83671415d8e6829d8fc2a932b006b49d2000000000100010000000000000000000000000000000000000000000000000000000000000004000000000000000120000000000000000000000000000000000000000000546f6b656e4272696467650100000002000000000000000000000000e7000000000000000000000000000000000000b1")
	if err != nil {
		panic(err)
	}
	tokenbridge.RegisterChain(cross(cur), raw)
	vault := chain.PackageAddress("gno.land/r/wormhole/tokenbridge")
	user := chain.PackageAddress("gno.land/r/wormhole_test/user")
	recipient := [32]byte{31: 0xee}
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole/tokenbridge/logic/v1"))
	testing.IssueCoins(vault, chain.NewCoins(chain.NewCoin("ugnot", 1000)))
	println(tokenbridge.LockAndPublish(cross(cur), user, 1000, 2, recipient, 10, 0), tokenbridge.LockedGNOT())
	testing.IssueCoins(vault, chain.NewCoins(chain.NewCoin("ugnot", 7)))
	println(tokenbridge.LockAndPublishWithPayload(cross(cur), user, 7, 2, recipient, []byte("go"), 3),
		tokenbridge.LockedGNOT())
	println(tokenbridge.PublishGNOTMeta(cross(cur), 1))
	usdc := tb.Origin{Chain: 2, Address: [32]byte{31: 0x0c}}
	m := tb.AssetMeta{Token: usdc, Decimals: 6}
	copy(m.Symbol[:], "USDC")
	copy(m.Name[:], "USD Coin")
	tokenbridge.CreateWrapped(cross(cur), m, [32]byte{})
	tokenbridge.Mint(cross(cur), usdc, user, 500)
	println(tokenbridge.BurnAndPublish(cross(cur), usdc, user, 200, 2, recipient, 5, 4),
		tokenbridge.BalanceOf("USDC", user), tokenbridge.TotalSupply("USDC"))
	println(tokenbridge.BurnAndPublishWithPayload(cross(cur), usdc, user, 300, 2, recipient, []byte("hi"), 2),
		tokenbridge.BalanceOf("USDC", user), tokenbridge.TotalSupply("USDC"))
}

// Output:
// 0 1000
// 1 1007
// 2
// 3 300 300
// 4 0 0

// Events:
// [
//   {
//     "type": "PeerRegistered",
//     "attrs": [
//       {
//         "key": "chain",
//         "value": "2"
//       },
//       {
//         "key": "emitter",
//         "value": "000000000000000000000000e7000000000000000000000000000000000000b1"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "WormholeMessage",
//     "attrs": [
//       {
//         "key": "emitter",
//         "value": "000000000000000000000000ec284bb840cb6b26cedd71e45561c6c09d2c42d3"
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
//         "value": "0100000000000000000000000000000000000000000000000000000000000003e80134c34cde0720c7dfefda9794eb4ba7b9daadf126a6692b760ad020f943390dffff00000000000000000000000000000000000000000000000000000000000000ee0002000000000000000000000000000000000000000000000000000000000000000a"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/core"
//   },
//   {
//     "type": "WormholeTransferOut",
//     "attrs": [
//       {
//         "key": "token_chain",
//         "value": "65535"
//       },
//       {
//         "key": "token_address",
//         "value": "0134c34cde0720c7dfefda9794eb4ba7b9daadf126a6692b760ad020f943390d"
//       },
//       {
//         "key": "amount",
//         "value": "1000"
//       },
//       {
//         "key": "sender",
//         "value": "g1ergv5890fm0auua4kmsqvd2hxux9u52gnfe5yj"
//       },
//       {
//         "key": "sequence",
//         "value": "0"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "WormholeMessage",
//     "attrs": [
//       {
//         "key": "emitter",
//         "value": "000000000000000000000000ec284bb840cb6b26cedd71e45561c6c09d2c42d3"
//       },
//       {
//         "key": "sequence",
//         "value": "1"
//       },
//       {
//         "key": "nonce",
//         "value": "3"
//       },
//       {
//         "key": "consistency",
//         "value": "1"
//       },
//       {
//         "key": "payload",
//         "value": "0300000000000000000000000000000000000000000000000000000000000000070134c34cde0720c7dfefda9794eb4ba7b9daadf126a6692b760ad020f943390dffff00000000000000000000000000000000000000000000000000000000000000ee0002000000000000000000000000c8d0ca1caf4edfde73b5b6e0063557370c5e5148676f"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/core"
//   },
//   {
//     "type": "WormholeTransferOut",
//     "attrs": [
//       {
//         "key": "token_chain",
//         "value": "65535"
//       },
//       {
//         "key": "token_address",
//         "value": "0134c34cde0720c7dfefda9794eb4ba7b9daadf126a6692b760ad020f943390d"
//       },
//       {
//         "key": "amount",
//         "value": "7"
//       },
//       {
//         "key": "sender",
//         "value": "g1ergv5890fm0auua4kmsqvd2hxux9u52gnfe5yj"
//       },
//       {
//         "key": "sequence",
//         "value": "1"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "WormholeMessage",
//     "attrs": [
//       {
//         "key": "emitter",
//         "value": "000000000000000000000000ec284bb840cb6b26cedd71e45561c6c09d2c42d3"
//       },
//       {
//         "key": "sequence",
//         "value": "2"
//       },
//       {
//         "key": "nonce",
//         "value": "1"
//       },
//       {
//         "key": "consistency",
//         "value": "1"
//       },
//       {
//         "key": "payload",
//         "value": "020134c34cde0720c7dfefda9794eb4ba7b9daadf126a6692b760ad020f943390dffff06474e4f5400000000000000000000000000000000000000000000000000000000476e6f2e6c616e64000000000000000000000000000000000000000000000000"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/core"
//   },
//   {
//     "type": "NewToken",
//     "attrs": [
//       {
//         "key": "token",
//         "value": "gno.land/r/wormhole/tokenbridge.USDC.0000001"
//       },
//       {
//         "key": "name",
//         "value": "USD Coin (Wormhole)"
//       },
//       {
//         "key": "symbol",
//         "value": "USDC"
//       },
//       {
//         "key": "decimals",
//         "value": "6"
//       }
//     ],
//     "pkg_path": "gno.land/p/nt/grc20/v0"
//   },
//   {
//     "type": "register",
//     "attrs": [
//       {
//         "key": "token_path",
//         "value": "gno.land/r/wormhole/tokenbridge.USDC"
//       },
//       {
//         "key": "pkgpath",
//         "value": "gno.land/r/wormhole/tokenbridge"
//       },
//       {
//         "key": "slug",
//         "value": ""
//       },
//       {
//         "key": "symbol",
//         "value": "USDC"
//       }
//     ],
//     "pkg_path": "gno.land/r/nt/grc20reg/v0"
//   },
//   {
//     "type": "WrappedCreated",
//     "attrs": [
//       {
//         "key": "token_chain",
//         "value": "2"
//       },
//       {
//         "key": "token_address",
//         "value": "000000000000000000000000000000000000000000000000000000000000000c"
//       },
//       {
//         "key": "symbol",
//         "value": "USDC"
//       },
//       {
//         "key": "token_id",
//         "value": "gno.land/r/wormhole/tokenbridge.USDC.0000001"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "Transfer",
//     "attrs": [
//       {
//         "key": "token",
//         "value": "gno.land/r/wormhole/tokenbridge.USDC.0000001"
//       },
//       {
//         "key": "from",
//         "value": ""
//       },
//       {
//         "key": "to",
//         "value": "g1ergv5890fm0auua4kmsqvd2hxux9u52gnfe5yj"
//       },
//       {
//         "key": "value",
//         "value": "500"
//       }
//     ],
//     "pkg_path": "gno.land/p/nt/grc20/v0"
//   },
//   {
//     "type": "WormholeMessage",
//     "attrs": [
//       {
//         "key": "emitter",
//         "value": "000000000000000000000000ec284bb840cb6b26cedd71e45561c6c09d2c42d3"
//       },
//       {
//         "key": "sequence",
//         "value": "3"
//       },
//       {
//         "key": "nonce",
//         "value": "4"
//       },
//       {
//         "key": "consistency",
//         "value": "1"
//       },
//       {
//         "key": "payload",
//         "value": "0100000000000000000000000000000000000000000000000000000000000000c8000000000000000000000000000000000000000000000000000000000000000c000200000000000000000000000000000000000000000000000000000000000000ee00020000000000000000000000000000000000000000000000000000000000000005"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/core"
//   },
//   {
//     "type": "Transfer",
//     "attrs": [
//       {
//         "key": "token",
//         "value": "gno.land/r/wormhole/tokenbridge.USDC.0000001"
//       },
//       {
//         "key": "from",
//         "value": "g1ergv5890fm0auua4kmsqvd2hxux9u52gnfe5yj"
//       },
//       {
//         "key": "to",
//         "value": ""
//       },
//       {
//         "key": "value",
//         "value": "200"
//       }
//     ],
//     "pkg_path": "gno.land/p/nt/grc20/v0"
//   },
//   {
//     "type": "WormholeTransferOut",
//     "attrs": [
//       {
//         "key": "token_chain",
//         "value": "2"
//       },
//       {
//         "key": "token_address",
//         "value": "000000000000000000000000000000000000000000000000000000000000000c"
//       },
//       {
//         "key": "amount",
//         "value": "200"
//       },
//       {
//         "key": "sender",
//         "value": "g1ergv5890fm0auua4kmsqvd2hxux9u52gnfe5yj"
//       },
//       {
//         "key": "sequence",
//         "value": "3"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "WormholeMessage",
//     "attrs": [
//       {
//         "key": "emitter",
//         "value": "000000000000000000000000ec284bb840cb6b26cedd71e45561c6c09d2c42d3"
//       },
//       {
//         "key": "sequence",
//         "value": "4"
//       },
//       {
//         "key": "nonce",
//         "value": "2"
//       },
//       {
//         "key": "consistency",
//         "value": "1"
//       },
//       {
//         "key": "payload",
//         "value": "03000000000000000000000000000000000000000000000000000000000000012c000000000000000000000000000000000000000000000000000000000000000c000200000000000000000000000000000000000000000000000000000000000000ee0002000000000000000000000000c8d0ca1caf4edfde73b5b6e0063557370c5e51486869"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/core"
//   },
//   {
//     "type": "Transfer",
//     "attrs": [
//       {
//         "key": "token",
//         "value": "gno.land/r/wormhole/tokenbridge.USDC.0000001"
//       },
//       {
//         "key": "from",
//         "value": "g1ergv5890fm0auua4kmsqvd2hxux9u52gnfe5yj"
//       },
//       {
//         "key": "to",
//         "value": ""
//       },
//       {
//         "key": "value",
//         "value": "300"
//       }
//     ],
//     "pkg_path": "gno.land/p/nt/grc20/v0"
//   },
//   {
//     "type": "WormholeTransferOut",
//     "attrs": [
//       {
//         "key": "token_chain",
//         "value": "2"
//       },
//       {
//         "key": "token_address",
//         "value": "000000000000000000000000000000000000000000000000000000000000000c"
//       },
//       {
//         "key": "amount",
//         "value": "300"
//       },
//       {
//         "key": "sender",
//         "value": "g1ergv5890fm0auua4kmsqvd2hxux9u52gnfe5yj"
//       },
//       {
//         "key": "sequence",
//         "value": "4"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   }
// ]
