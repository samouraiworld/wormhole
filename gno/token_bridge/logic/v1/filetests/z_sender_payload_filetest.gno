// PKGPATH: gno.land/r/wormhole_test/senderpayload
package senderpayload

// A realm sender's payload 3: tbsender's TransferWrappedWithPayload burns its
// own tokens and publishes a payload-3 transfer whose fromAddress is tbsender's
// 20 bytes, left-padded, never an argument, and WormholeTransferOut names
// tbsender as the sender.

import (
	"chain"
	"encoding/hex"
	"testing"
	"time"

	tb "gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/tokenbridge"
	v1 "gno.land/r/wormhole/tokenbridge/logic/v1"
	"gno.land/r/wormhole_test/tbsender"
)

func wire(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return b
}

func main(cur realm) {
	ctx := testing.GetContext()
	ctx.Time = time.Unix(1_800_000_000, 0)
	testing.SetContext(ctx)
	tokenbridge.RegisterChain(cross(cur), wire("01000000030d00702242a4cbc01e3c80ec68af614c764bdbaa92217be40fc30ac79258ac38599c416c05982b2926dee53f12ec7f88e89cc00e73d669e49fe4a4b0e1b5104ef1700001cacb1e94ac2c109f57d82e1401c22b72cf82fd7492513684c45f90935255ee992325f364d52283b6698d233bcba28e9b255a88a0ded1bd554060a56ead01cb8f000297f4d3f152ddc1c1a86da86b515d1207f89844de2335b42693660322308f7ec91362f13ec12f374972d6ec6f24c3b79c72c1ed7eb0bff4481823cd39d3d1a383010395236c4fe5481a78a0b6881e3003aa175503e0dc7e61fe28e3708da726c4559b1778cc60e4e5598eca27c2907f8e6d3cf93a317edec601c4d6a8e4caae149ed00104a4938eee1603b563158eaf7efa3d4567ade9a61aee36f7aae50de8d6ea76b2f0179d8494b00b3ad2747166ac1bf4f11af95b1956bcb076ad057aea0fc98f13a500057ec86196b6b8bf154c27bde55ef02ccc6957571bafcf57515c112856e71d84255002548480db3f46fb9f6e12aca44287618ff31b3947ba413b64d96fe602daad0006efb7ff1394a7672908e5fc1e36ba19534b5db80cffe6803593a12fc51b84440e4e52a0622d381269abb63c411174f4f4fa9d4f5aded3750f0a87a51e9deeeeac01070730771bcf1d356247cfa25d58066e36a03cb387d091277e2ad1eb20ad1645d8091ed6b41166c6fcb73db1373f630fe6e8b6bd479be01e35952a9741e94b72b00108d4e806b0bfbaf8130366386f3be3c7d4a6ccd53fcc88342219a6597001a47bba3360ac7ecba68f14ef19e06adb8a98b404badbfcb01c17ce83c4195011fb89880109f4159a6c9195e0a5c06ca12c5e6a2706e5e765a87f1d5691bc858def80f3c0fb675311efa19f8a3dce3f9889de16731ef4f0899c4e75aa72d7a8d2a7be303e94010a8f96de37f9269664cde3d2271471703415f8147bacc8f82fdac786817e47a442356e2368d953024049243db9032f22b0d8c6659dd30942faafb157b0f3c97452010b66ede326db9247cdc1cb72b99193fe2f9791c80e1d0c34ac2c4ad2a59b8c50404784a48a756f8111da8a760bfed83d7af681c6f569d44196243b014b02daa4ff000c0eaea9e5bf052c23b52f19a77711da2d8f5c352bae8b556290d9f40a862a465f44c5438527b4b6d99a97b201700277984e8989ec7dba41e7ded5ceb4b693cd36006b49d200000000070001000000000000000000000000000000000000000000000000000000000000000400000000000000c901000000000000000000000000000000000000000000546f6b656e42726964676501ffff0002a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf"))
	v1.CreateWrapped(cross(cur), wire("01000000030d003b9fd5af401029670f9d7a47d876ece2c38347c080d819d4538fe5ca72fd65c201169d37c99afb5d99a66e6d285ddd60676c643337818dc7e12d1758e34aa2be0101da9ecd659914567e82be5f64d34659d5dade852aaeaee81bdf27270fc1faf99c12b78afeb2001278ba387fcd467c6a2ad62c8b089f4974f19f289a34636ab27900027eddf1604c34c3d0bfaf8b0274a0418c3b890ec07fc17ef94af08814b5d513db798ba583b8faa86c15477d804a3544014afe32af93998fcc865102c2ef79b0430103e9d472de5c810491f92100c87eeeebc1bafb91cbd0a6162c4498e4a6914c937b4e2b3de3436b5f440c0b8696f72eec0161560f8f0138785e1d711973c797c6400004267319deaf215262713c082f127ce686f0f2df275c2068b9f497fa44c8d8a7a07cee40a8fa3c51a405f364c5a7ef1d2e5ebd32dccd2a8800a905528e7ded6ff1010516ecf6e00300ff5a1a41b4888c5a4b2a83be44589ecf8f923964dbb47308c0b314583f70a01dddadaf36abd89a099e5a60ef2717304b18de19fae581fe119b2a0106f5e4af8b355ac44cbbcb2d97c27b55291e7c6b26d3560e670356f1d9a2cacc601ffe1d31f632343b2d3ea0aa5ff31bb6e9d9a3f1bed6893e106e6b3b21de089f00076aca12d74da2541ebba4c593f3d4b88b1a2f8ec3b01b7225f30824efb86a52a06c29369fb421e8004eeaaed4598156b1a657393a7df5c91c60b772fb17e9df8800085559efe593c2a495711ff0837d18bba7333b174beb062c464f26b8b569c4ff106d82b7b927acf151a290747452bb6f93a7a76468beac151ea42eca66b957bb00000907ae424e7524a3dc1e77e9349cba39849df55f02118564af1152991f5a8abc1f4bb22eb06a239ac29dc6ba77458148284f686b25595849f88b108640df26a2f6010afbaa29cf7aee6f554d509d6dbda7491004769233355fbf317f8a3abc5171f42618675ddf5d8aa4aa3191967f38c6662eb95f5aadb39e582013b3eb7fe5bed09e000b5cff4b149f1917d0f3db16c345b68124061ee83f66f2101448f6abc34e29aa115fb93ab6cf40441e6291c68b512bbfc9c915a193b922134991d84773057d5cb6000c493c629fbcdfdecf3eed4075e4470682cf801c9b5126157e07be2a76cef7180d24f4c37f44c4bf34ebb94f374ab6e003a9144a43f1a342ae76396124c940c932016b49d200000000070002a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf00000000000000010102000000000000000000000000a000000000000000000000000000000000000048000206555344430000000000000000000000000000000000000000000000000000000055534420436f696e000000000000000000000000000000000000000000000000"))
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole/tokenbridge/logic/v1"))
	tokenbridge.Mint(cross(cur), tb.Origin{Chain: 2, Address: [32]byte{12: 0xa0, 31: 0x48}},
		chain.PackageAddress("gno.land/r/wormhole_test/tbsender"), 50)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/realmcaller"))
	println(tbsender.SendWrappedWithPayload(cross(cur), "USDC", 40, 2, [32]byte{31: 0xee}, []byte("from a realm")))
}

// Output:
// 0

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
//         "value": "g1y8xqrmejdly3tj87cggy3a4huqast2jk85ufdf"
//       },
//       {
//         "key": "value",
//         "value": "50"
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
//         "value": "0"
//       },
//       {
//         "key": "consistency",
//         "value": "1"
//       },
//       {
//         "key": "payload",
//         "value": "030000000000000000000000000000000000000000000000000000000000000028000000000000000000000000a000000000000000000000000000000000000048000200000000000000000000000000000000000000000000000000000000000000ee000200000000000000000000000021cc01ef326fc915c8fec21048f6b7e03b05aa5666726f6d2061207265616c6d"
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
//         "value": "g1y8xqrmejdly3tj87cggy3a4huqast2jk85ufdf"
//       },
//       {
//         "key": "to",
//         "value": ""
//       },
//       {
//         "key": "value",
//         "value": "40"
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
//         "value": "40"
//       },
//       {
//         "key": "sender",
//         "value": "g1y8xqrmejdly3tj87cggy3a4huqast2jk85ufdf"
//       },
//       {
//         "key": "sequence",
//         "value": "0"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   }
// ]
