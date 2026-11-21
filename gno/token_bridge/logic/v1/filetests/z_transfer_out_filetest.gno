// PKGPATH: gno.land/r/wormhole_test/transferout
package transferout

// Transfers out at Core's message fee of 0. A user calls each
// entry point directly, attaching exactly the GNOT amount, or nothing for a
// wrapped asset. TransferGNOT moves the 1,000 ugnot attached to the logic on to
// the vault, which locks them and publishes one transfer, and the outbound
// window counts them. The payload-3 forms carry the caller's 20 bytes, and a
// wrapped transfer burns the user's own tokens. AttestGNOT publishes GNOT's
// AssetMeta. The events show each message: the payload Core publishes, and the
// vault's WormholeTransferOut.

import (
	"chain"
	"chain/banker"
	"encoding/hex"
	"testing"
	"time"

	tb "gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/core"
	"gno.land/r/wormhole/tokenbridge"
	v1 "gno.land/r/wormhole/tokenbridge/logic/v1"
)

const (
	logicPath = "gno.land/r/wormhole/tokenbridge/logic/v1"
	vaultPath = "gno.land/r/wormhole/tokenbridge"
	usdc      = "000000000000000000000000a000000000000000000000000000000000000048"
)

func wire(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return b
}

func ugnot(a address) int64 {
	return banker.NewReadonlyBanker().GetCoin(a, "ugnot")
}

// deposit stands for a MsgCall's -send: the origin call attaches coins, which the
// bank credits to the logic before it runs.
func deposit(amount int64) {
	coins := chain.NewCoins(chain.NewCoin("ugnot", amount))
	testing.SetOriginSend(coins)
	testing.IssueCoins(chain.PackageAddress(logicPath), coins)
}

func main(cur realm) {
	ctx := testing.GetContext()
	ctx.Time = time.Unix(1_800_000_000, 0)
	testing.SetContext(ctx)
	user := chain.PackageAddress("gno.land/r/wormhole_test/user")
	vaultAddr := chain.PackageAddress(vaultPath)
	tokenbridge.RegisterChain(cross(cur), wire("01000000030d00702242a4cbc01e3c80ec68af614c764bdbaa92217be40fc30ac79258ac38599c416c05982b2926dee53f12ec7f88e89cc00e73d669e49fe4a4b0e1b5104ef1700001cacb1e94ac2c109f57d82e1401c22b72cf82fd7492513684c45f90935255ee992325f364d52283b6698d233bcba28e9b255a88a0ded1bd554060a56ead01cb8f000297f4d3f152ddc1c1a86da86b515d1207f89844de2335b42693660322308f7ec91362f13ec12f374972d6ec6f24c3b79c72c1ed7eb0bff4481823cd39d3d1a383010395236c4fe5481a78a0b6881e3003aa175503e0dc7e61fe28e3708da726c4559b1778cc60e4e5598eca27c2907f8e6d3cf93a317edec601c4d6a8e4caae149ed00104a4938eee1603b563158eaf7efa3d4567ade9a61aee36f7aae50de8d6ea76b2f0179d8494b00b3ad2747166ac1bf4f11af95b1956bcb076ad057aea0fc98f13a500057ec86196b6b8bf154c27bde55ef02ccc6957571bafcf57515c112856e71d84255002548480db3f46fb9f6e12aca44287618ff31b3947ba413b64d96fe602daad0006efb7ff1394a7672908e5fc1e36ba19534b5db80cffe6803593a12fc51b84440e4e52a0622d381269abb63c411174f4f4fa9d4f5aded3750f0a87a51e9deeeeac01070730771bcf1d356247cfa25d58066e36a03cb387d091277e2ad1eb20ad1645d8091ed6b41166c6fcb73db1373f630fe6e8b6bd479be01e35952a9741e94b72b00108d4e806b0bfbaf8130366386f3be3c7d4a6ccd53fcc88342219a6597001a47bba3360ac7ecba68f14ef19e06adb8a98b404badbfcb01c17ce83c4195011fb89880109f4159a6c9195e0a5c06ca12c5e6a2706e5e765a87f1d5691bc858def80f3c0fb675311efa19f8a3dce3f9889de16731ef4f0899c4e75aa72d7a8d2a7be303e94010a8f96de37f9269664cde3d2271471703415f8147bacc8f82fdac786817e47a442356e2368d953024049243db9032f22b0d8c6659dd30942faafb157b0f3c97452010b66ede326db9247cdc1cb72b99193fe2f9791c80e1d0c34ac2c4ad2a59b8c50404784a48a756f8111da8a760bfed83d7af681c6f569d44196243b014b02daa4ff000c0eaea9e5bf052c23b52f19a77711da2d8f5c352bae8b556290d9f40a862a465f44c5438527b4b6d99a97b201700277984e8989ec7dba41e7ded5ceb4b693cd36006b49d200000000070001000000000000000000000000000000000000000000000000000000000000000400000000000000c901000000000000000000000000000000000000000000546f6b656e42726964676501ffff0002a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf"))
	v1.CreateWrapped(cross(cur), wire("01000000030d003b9fd5af401029670f9d7a47d876ece2c38347c080d819d4538fe5ca72fd65c201169d37c99afb5d99a66e6d285ddd60676c643337818dc7e12d1758e34aa2be0101da9ecd659914567e82be5f64d34659d5dade852aaeaee81bdf27270fc1faf99c12b78afeb2001278ba387fcd467c6a2ad62c8b089f4974f19f289a34636ab27900027eddf1604c34c3d0bfaf8b0274a0418c3b890ec07fc17ef94af08814b5d513db798ba583b8faa86c15477d804a3544014afe32af93998fcc865102c2ef79b0430103e9d472de5c810491f92100c87eeeebc1bafb91cbd0a6162c4498e4a6914c937b4e2b3de3436b5f440c0b8696f72eec0161560f8f0138785e1d711973c797c6400004267319deaf215262713c082f127ce686f0f2df275c2068b9f497fa44c8d8a7a07cee40a8fa3c51a405f364c5a7ef1d2e5ebd32dccd2a8800a905528e7ded6ff1010516ecf6e00300ff5a1a41b4888c5a4b2a83be44589ecf8f923964dbb47308c0b314583f70a01dddadaf36abd89a099e5a60ef2717304b18de19fae581fe119b2a0106f5e4af8b355ac44cbbcb2d97c27b55291e7c6b26d3560e670356f1d9a2cacc601ffe1d31f632343b2d3ea0aa5ff31bb6e9d9a3f1bed6893e106e6b3b21de089f00076aca12d74da2541ebba4c593f3d4b88b1a2f8ec3b01b7225f30824efb86a52a06c29369fb421e8004eeaaed4598156b1a657393a7df5c91c60b772fb17e9df8800085559efe593c2a495711ff0837d18bba7333b174beb062c464f26b8b569c4ff106d82b7b927acf151a290747452bb6f93a7a76468beac151ea42eca66b957bb00000907ae424e7524a3dc1e77e9349cba39849df55f02118564af1152991f5a8abc1f4bb22eb06a239ac29dc6ba77458148284f686b25595849f88b108640df26a2f6010afbaa29cf7aee6f554d509d6dbda7491004769233355fbf317f8a3abc5171f42618675ddf5d8aa4aa3191967f38c6662eb95f5aadb39e582013b3eb7fe5bed09e000b5cff4b149f1917d0f3db16c345b68124061ee83f66f2101448f6abc34e29aa115fb93ab6cf40441e6291c68b512bbfc9c915a193b922134991d84773057d5cb6000c493c629fbcdfdecf3eed4075e4470682cf801c9b5126157e07be2a76cef7180d24f4c37f44c4bf34ebb94f374ab6e003a9144a43f1a342ae76396124c940c932016b49d200000000070002a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf00000000000000010102000000000000000000000000a000000000000000000000000000000000000048000206555344430000000000000000000000000000000000000000000000000000000055534420436f696e000000000000000000000000000000000000000000000000"))
	testing.SetRealm(testing.NewUserRealm(chain.PackageAddress("gno.land/r/wormhole_test/relayer")))
	v1.Redeem(cross(cur), wire("01000000030d003c4996a4555cd5ddf24111deb7f6721ef94feb1d11956fc521af7d9c2313d9386161f8d0f2659cdece77cb5c35fd001bea870cf9c63c2347ba8b7b4af43ae9dc000178dd39255f3f483980be83cc147705a635bf78aa34ca770a86d0ca4fcf6f3a1938590d298326eb561a16bccb7e0e2bcd159a34a87ef8efc1364d19dce7247c2900025e0b549e76b37ec5b1166ea83355916e66facee3b9b72ba86fa1d2031167f15f7fd47301b8c8cc71731f45359eeeb1c0ba4d93cb11569065db5fc699973cf95600035d548d6121795129efa92e95f1353206b91ec4c71afe77c8caac17fac4582c0e1c25a8ff9c2010880896f960af9e8c659af80834c65a7388f9675b56e804e8f700049cec4f1f94de59b57ec637080db11bea9ee85c313ddaa1de4680de931eb31a5f0a776aaca4dd67a9b545672d84eb387595c2e2ef0d1ce5449cccdd8c9430aa5901056a87add34374097f7bde13ac66d1b9d4c1c4d9f036521a14b50c24c029c281d83be218a83656baf87c821c5752ea867463cc07d9a4db744058139b7f2531d3e40106d3ff5cc813f2d263d981a2bc170a336144037eb4cc584c93d203148bd2d63ea20338bca9cd3fbd4049f566d11217c1bb734c3a98fdb4dc51032475727e19803f01077a77bb7d874021a59bd0f57c62025636d5f07a8223712bae29171e58eb3043de3eaebe5f6ccf7c01a4248e19922738e5dea3f03a15e3bbbb40007a39e3910bcf00087ea5c94781d03e95f2b07712aed377d6918ed904ed0e8965e951f98950febc1b01e12f3cac5bda632b1e3cf069e03ce1895b0cd7af6c0a337b5436f0f01ed4e60109b3e0ed06b69910f8ae71aedb653bccf28ab8cb38c97126c6c39b03fd108ea7d16b3b576f788257e0eae4f4bf38681efa6d47529588d8f0aef61a3704dffbb248010a61e50e82671d612e9f5ff24d4079a71fba5e901a7f8e330d4f70f0d86e02c07e32e9fca9c0b5fbf83ae5d7d9066e1b2eacbe7c9fa74dd2e2bc74e43685880a53000b377131f0aebcf005c889c8a7beb9646fbefa87c3a431a8af5d4678346c3ef3650cc70507acebcd6dee26feafaf5427441956fdbd458c9dc28892df2abb7535d9000cbef3a63be29a86a99a20230a09ff5bb1497080b72ddecfae6e3cfd562c6d7b4371accda0b9f2dcada23e6931f221fea9e5fb24077319d5c4fabdd2307dc56dc5006b49d200000000070002a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf000000000000000e010100000000000000000000000000000000000000000000000000000000000007d0000000000000000000000000a0000000000000000000000000000000000000480002000000000000000000000000c8d0ca1caf4edfde73b5b6e0063557370c5e5148ffff0000000000000000000000000000000000000000000000000000000000000000"))
	token := tb.GNOTAddress()
	gnot := hex.EncodeToString(token[:])
	recipient := [32]byte{31: 0xee}

	testing.SetRealm(testing.NewUserRealm(user))
	deposit(1000)
	seq := v1.TransferGNOT(cross(cur), 1000, 2, recipient, 10, 7)
	_, _, _, outbound, _, _ := v1.Limits(65535, gnot)
	println(seq, ugnot(vaultAddr), tokenbridge.LockedGNOT(), ugnot(chain.PackageAddress(logicPath)), outbound)
	deposit(300)
	println(v1.TransferGNOTWithPayload(cross(cur), 300, 2, recipient, []byte("gnot app"), 8))
	deposit(0)
	println(v1.TransferWrapped(cross(cur), "USDC", 600, 2, recipient, 6, 9))
	deposit(0)
	println(v1.TransferWrappedWithPayload(cross(cur), "USDC", 400, 2, recipient, []byte("usdc app"), 10))
	deposit(0)
	println(v1.AttestGNOT(cross(cur), 11))
	_, _, _, gnotOut, _, _ := v1.Limits(65535, gnot)
	_, _, _, usdcOut, _, _ := v1.Limits(2, usdc)
	println(tokenbridge.LockedGNOT(), ugnot(vaultAddr), tokenbridge.BalanceOf("USDC", user),
		tokenbridge.TotalSupply("USDC"), gnotOut, usdcOut, core.MessageFee())
}

// Output:
// 0 1000 1000 0 1000
// 1
// 2
// 3
// 4
// 1300 1300 1000 1000 1300 1000 0

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
//         "value": "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
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
//         "value": "000000000000000000000000a000000000000000000000000000000000000048"
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
//     "type": "TransferRedeemed",
//     "attrs": [
//       {
//         "key": "emitter_chain",
//         "value": "2"
//       },
//       {
//         "key": "emitter_address",
//         "value": "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf"
//       },
//       {
//         "key": "sequence",
//         "value": "14"
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
//         "value": "2000"
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
//         "value": "8"
//       },
//       {
//         "key": "consistency",
//         "value": "1"
//       },
//       {
//         "key": "payload",
//         "value": "03000000000000000000000000000000000000000000000000000000000000012c0134c34cde0720c7dfefda9794eb4ba7b9daadf126a6692b760ad020f943390dffff00000000000000000000000000000000000000000000000000000000000000ee0002000000000000000000000000c8d0ca1caf4edfde73b5b6e0063557370c5e5148676e6f7420617070"
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
//         "value": "300"
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
//         "value": "9"
//       },
//       {
//         "key": "consistency",
//         "value": "1"
//       },
//       {
//         "key": "payload",
//         "value": "010000000000000000000000000000000000000000000000000000000000000258000000000000000000000000a000000000000000000000000000000000000048000200000000000000000000000000000000000000000000000000000000000000ee00020000000000000000000000000000000000000000000000000000000000000006"
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
//         "value": "600"
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
//         "value": "000000000000000000000000a000000000000000000000000000000000000048"
//       },
//       {
//         "key": "amount",
//         "value": "600"
//       },
//       {
//         "key": "sender",
//         "value": "g1ergv5890fm0auua4kmsqvd2hxux9u52gnfe5yj"
//       },
//       {
//         "key": "sequence",
//         "value": "2"
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
//         "value": "3"
//       },
//       {
//         "key": "nonce",
//         "value": "10"
//       },
//       {
//         "key": "consistency",
//         "value": "1"
//       },
//       {
//         "key": "payload",
//         "value": "030000000000000000000000000000000000000000000000000000000000000190000000000000000000000000a000000000000000000000000000000000000048000200000000000000000000000000000000000000000000000000000000000000ee0002000000000000000000000000c8d0ca1caf4edfde73b5b6e0063557370c5e51487573646320617070"
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
//         "value": "400"
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
//         "value": "000000000000000000000000a000000000000000000000000000000000000048"
//       },
//       {
//         "key": "amount",
//         "value": "400"
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
//         "value": "11"
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
//   }
// ]
