// PKGPATH: gno.land/r/wormhole_test/govevents
package govevents

// The direct entry points' events, schema v1, each from one call on a fresh
// vault: PeerRegistered, PauserAddressesSet, Paused, Unpaused, UnpauseExpired,
// Frozen, ChainIDProposed (twice in a row: a new proposal replaces the old one
// with no ChainIDCancelled), ChainIDCancelled (by the freezer while live, by a
// change of unpauser, and by the lapse once a successful call runs under
// another chain ID), ChainIDConfirmed and LogicSwitched.

import (
	"chain"
	"encoding/hex"
	"testing"
	"time"

	"gno.land/r/wormhole/tokenbridge"
)

const (
	start     = 1_800_000_000
	day       = 86400
	pauser    = "gno.land/r/wormhole_test/pauser"
	freezer   = "gno.land/r/wormhole_test/freezer"
	unpauser  = "gno.land/r/wormhole_test/unpauser"
	unpauser2 = "gno.land/r/wormhole_test/unpauser2"
)

func wire(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return b
}

// at sets the block time and the runtime chain ID.
func at(unix int64, chainID string) {
	ctx := testing.GetContext()
	ctx.Time = time.Unix(unix, 0)
	ctx.ChainID = chainID
	testing.SetContext(ctx)
}

func main(cur realm) {
	user := chain.PackageAddress("gno.land/r/wormhole_test/user")
	at(start, "dev")
	testing.SetRealm(testing.NewUserRealm(user))
	tokenbridge.RegisterChain(cross(cur), wire("01000000030d00702242a4cbc01e3c80ec68af614c764bdbaa92217be40fc30ac79258ac38599c416c05982b2926dee53f12ec7f88e89cc00e73d669e49fe4a4b0e1b5104ef1700001cacb1e94ac2c109f57d82e1401c22b72cf82fd7492513684c45f90935255ee992325f364d52283b6698d233bcba28e9b255a88a0ded1bd554060a56ead01cb8f000297f4d3f152ddc1c1a86da86b515d1207f89844de2335b42693660322308f7ec91362f13ec12f374972d6ec6f24c3b79c72c1ed7eb0bff4481823cd39d3d1a383010395236c4fe5481a78a0b6881e3003aa175503e0dc7e61fe28e3708da726c4559b1778cc60e4e5598eca27c2907f8e6d3cf93a317edec601c4d6a8e4caae149ed00104a4938eee1603b563158eaf7efa3d4567ade9a61aee36f7aae50de8d6ea76b2f0179d8494b00b3ad2747166ac1bf4f11af95b1956bcb076ad057aea0fc98f13a500057ec86196b6b8bf154c27bde55ef02ccc6957571bafcf57515c112856e71d84255002548480db3f46fb9f6e12aca44287618ff31b3947ba413b64d96fe602daad0006efb7ff1394a7672908e5fc1e36ba19534b5db80cffe6803593a12fc51b84440e4e52a0622d381269abb63c411174f4f4fa9d4f5aded3750f0a87a51e9deeeeac01070730771bcf1d356247cfa25d58066e36a03cb387d091277e2ad1eb20ad1645d8091ed6b41166c6fcb73db1373f630fe6e8b6bd479be01e35952a9741e94b72b00108d4e806b0bfbaf8130366386f3be3c7d4a6ccd53fcc88342219a6597001a47bba3360ac7ecba68f14ef19e06adb8a98b404badbfcb01c17ce83c4195011fb89880109f4159a6c9195e0a5c06ca12c5e6a2706e5e765a87f1d5691bc858def80f3c0fb675311efa19f8a3dce3f9889de16731ef4f0899c4e75aa72d7a8d2a7be303e94010a8f96de37f9269664cde3d2271471703415f8147bacc8f82fdac786817e47a442356e2368d953024049243db9032f22b0d8c6659dd30942faafb157b0f3c97452010b66ede326db9247cdc1cb72b99193fe2f9791c80e1d0c34ac2c4ad2a59b8c50404784a48a756f8111da8a760bfed83d7af681c6f569d44196243b014b02daa4ff000c0eaea9e5bf052c23b52f19a77711da2d8f5c352bae8b556290d9f40a862a465f44c5438527b4b6d99a97b201700277984e8989ec7dba41e7ded5ceb4b693cd36006b49d200000000070001000000000000000000000000000000000000000000000000000000000000000400000000000000c901000000000000000000000000000000000000000000546f6b656e42726964676501ffff0002a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf"))
	tokenbridge.SetPauserAddresses(cross(cur), wire("01000000030d00dbf41ee2ae64f7a02643822a4a22558b80044bd48df8657fb85131ae1e7a292872ddef95fb4de8da74a33540780ab0efad78a2753019aa19d92e85fb055422a600010c4dd71f4b51870cc654c4bf4e415694612218e2732652fef78eb694b20bc6a614f305d25a0a25bd1ba914ff106e3d8555fed844683b12c0f9a9b466bd0e57370102c03865e07a9c2c4203d81b796e3f3bb3cf515e304fd81dc746dc72e96b38f94b1c6b275d8bf238af3e8bde44f6dca4d53783eb15abbbef1333dec877d414b3c1010386cabda02ac06819ed6d187aa71351871f749f9b8e5c611af8c83260858cea003313bd0c9187399683ffc4fdd124c619fd14f7c211549364a6a191573f580bc00004c30c7b57fb4009ba8bf6e483f00607c52601a1be91547b775bf775f1e039c7682eddb012b0b5c00010549e6a25eccbbca1700a0ea4557fe804d326cb3586df5600052b9c6fd67fe9c4490079832d93f05d0d73f0b7721ed78678fdea4fa0c4e1589a231284776fde3ee138193f13f2f274442fbfc43b8b5111a419deda58fcb3786400061a7a967d33f6c0c0636f5e11479c737aa01d2343d58e833101ee8d77174c1a251822ac18be715d328238642be3582ba3bd4cfab5ed86450c4c45ce3f6a8b0c2e01074e483d7b0cdd2b85e90eac30deec72ed8770f00f692571e326252d706bef84317c8d5182106e540e3159b4a860e42737d496e904c435f6eb37f8d22af9f8936f0008fb5ce93583cb808bdd7d3c7a0ad72daa74b78790af89436667d5c545fce14b8e4b82cd41ecc72b1bfea579ac21b8f795e87792afd06cdbe28fedbb25c0fe1b0c010972ff7b66fa8775b92f5a2480d62c78a9efadb50b643c8bcd350845428d18800919976ba39fffa013e03b1749cfe84c337129674d49ed2168d21292f6006dba25010aa542a6260dc12c00691b01cd9e919c440939dc982cd68039d01a4b6dfdf411b036db88871c3a9bc96963ad5e17b6c671b33dd9ff83cc5815ad6c814c3b841219000bbbd5c9502000f7abd0699b2657fe6bc4dcbdff65a63b864ee281ddc4749aa69b014fa4a25622d895ba5edd5ef8a83472efe7ca609acba846fa7fdef515bae3d2010cb5523ff8be57d0d7e75c3334d416c53bd3588897968f9de4d3307a2acd6da19c0c26ebfdd6f13ca59406131a45eaec015b07d989a6eb89a4e25bbe8371dc7f8a016b49d200000000070001000000000000000000000000000000000000000000000000000000000000000400000000000000d601000000000000000000000000000000000000000000546f6b656e42726964676504ffff14514845a71a60dad8be03ba0cfab4f7a66d4b4c4714535a4d9144fbf9a2c490f9b68f63595781fee564146e741991ca9547c4d82d3e348340a6f17d369ee0"))
	testing.SetRealm(testing.NewCodeRealm(pauser))
	tokenbridge.Pause(cross(cur))
	testing.SetRealm(testing.NewCodeRealm(unpauser))
	tokenbridge.Unpause(cross(cur))
	testing.SetRealm(testing.NewCodeRealm(pauser))
	tokenbridge.Pause(cross(cur))
	at(start+5*day, "dev")
	testing.SetRealm(testing.NewUserRealm(user))
	tokenbridge.UnpauseExpired(cross(cur))
	testing.SetRealm(testing.NewCodeRealm(freezer))
	tokenbridge.Freeze(cross(cur))
	testing.SetRealm(testing.NewCodeRealm(unpauser))
	tokenbridge.Unpause(cross(cur))
	// Under another chain ID: a live proposal, replaced by a new one with no
	// ChainIDCancelled, which the freezer cancels.
	at(start+5*day, "forked")
	tokenbridge.ProposeChainID(cross(cur))
	at(start+5*day+1, "forked")
	tokenbridge.ProposeChainID(cross(cur))
	testing.SetRealm(testing.NewCodeRealm(freezer))
	tokenbridge.CancelChainID(cross(cur))
	// Another, which a change of unpauser cancels.
	testing.SetRealm(testing.NewCodeRealm(unpauser))
	tokenbridge.ProposeChainID(cross(cur))
	testing.SetRealm(testing.NewUserRealm(user))
	tokenbridge.SetPauserAddresses(cross(cur), wire("01000000030d005b2d99da468509bb302dfebfaf2951b5568cef220f19d015bb23354e6d35f818499f3dee0ea181dd51c42e84f0e723370d407c0dbc237c2cf8138cc803176ea40001870446d86e27f744680bd4c91f61ebc189386dce428c34ac56e1dfacd6d488df33bffdfac75725251e1fb05325c3cfed0f2678625332f202c17be65bf7517634000266469b3ad74d2ea91c7f08b339156ca1dca6731fdb293fd1e7530efc1c533c7a27b9ad4f49e792c7e69898bc687b02c34544a105eefff427ea36f466656df4e40003f53c7434cd7975dbe21261517ed039844d3a5543b002057984c775b8851a01a201bb927b87ea5e8494de541a74c3d607da88896b8f066ee90aed39af0b692a5100042e0d0fdbffac631c00af2360ccfc7d75a5e9c3183e6e5cb699f001262d9f03d822161d13d425701968cc74ca4d1fe5fabfe3ec5af343e6897d3103687f8f64dc0105ce4ba8efafdd7bd6de8debb94fecee85a300117f3a57c7be6cdb0f2a88d1dc8e74f074d0175909706a9994d48d194ee0d0aac5a8e3d8cc9855ded0e5acd069f400068174830c6b8cba36c56f4e877ad07a55ef9ba8fd6b0be9a354bfcef2a749a5ac2658879f1d74681ead2afab0528381cd6f2c28e68168b4a5a85f7d5b2709d1940107dff5ccef2702ce3197869ba3a27434bada561e56ec4282e6d7aac076fc13c42e4d26e2e233b9e0adbd75da726ee697a28d9f6fbee1743fd8d90742eb459b50af000881524e8d322af5736d8d185830cd6eb67c8e1d805a03282b8b3ef823ced28d5f177e983bb3127250e8701a7857f1c5d99850b9a661d6b8e68007aebee41ec122010951af25c7f56cfd5b89f1b0742c51d856f9e38063032b5013381a369956fabbf360d4a2ca1696e903d02bb13adfae39487582806f65e874a3bb892e69b6bb5e22000a4a6c7b375429933c3fd12859182c203a688b66498eb841ffa577324a888086a630bbcb622146c1aaf4f1a10a4e0f83260fdcf8e83b861bcf45b13097a02191c8000bed5fe09fe8cea8728e2874d600cbba17d80b99233f4fbae894c76e6d40a97e69451dc0b7620f9d291e311ad6d5298c790a2ee3dfdb7088034311339bbee9733d010c8936f7ee13c6656aff733e73cb63234e92b67c4a3bf726253a6f4fea9465675551dd901c2568f2ce8657c9704e96fb61080bd4c00dc922ffd4f9aa3dd33dd278016b49d200000000070001000000000000000000000000000000000000000000000000000000000000000400000000000000d701000000000000000000000000000000000000000000546f6b656e42726964676504ffff14514845a71a60dad8be03ba0cfab4f7a66d4b4c4714535a4d9144fbf9a2c490f9b68f63595781fee56414bd3a8b68f1ab4d7e03b92aed2e66f50e027e71a1"))
	// The new unpauser's, which a successful call under dev lapses.
	testing.SetRealm(testing.NewCodeRealm(unpauser2))
	tokenbridge.ProposeChainID(cross(cur))
	at(start+5*day, "dev")
	testing.SetRealm(testing.NewUserRealm(user))
	tokenbridge.RegisterChain(cross(cur), wire("01000000030d001a0bec8b6ad76877add9983588da435e8ce273117e33bc8e7ab37cf9fe32930d6d11e762fdc101cef79e8427d0d501bfd3c39428cfc911839300bb953ba7700c0101fd8fc26a99cbdbdd9a5bb0f374932aad2f5a653d16b6962155071d82d38a6d53382bbaa65100ca9113bc3cf2b7b4320bac2f05f988c6d7662b925c80e25f22d20102a1f35cb4252b78a7d6a413a02041dcce66214775ecc459d1a2660cf6a3c10b4b3801cba786a8c857c5844e0cbe1e316baa049cb1c9c221fae0c8f7b18dbf3c9d01033bf533c956fedb3527f233e8a3e5a6834a50b8bf8d4918f258602719944f84d47050f3610c8d294d3c57ce43c299afd0fbbb006a5cb2053a68a20353d0cad2d30104ab823acaf5ca420bd767b2c2a1ad7d3589cf5ac2c54610532cebe00253319aeb4edc672906ac8973abeece79445a31aa1ad50154eb4cff774b819c4829aedeef01052f960a03876b61998bc1bcb5246b167abce5312f771c0ccc9502f49f489f5ab911bea168f6b2b63571617981f3816217fb1c1a7b6b471b41afcfb83e16b05a4f010658621cbd46e647f82995934b2144e5c6232506ca708dd1a6b725b032eefc3fd1219b879951b5b99718c102aef944ed15967a596bc48e7d046b990e9648dc02f4010744a67b4018608f9817cc8f9065a4b2c3520e9f17295d398af1f991fc06cfe1cb156a3afd9380766606f4ac3d37eb75829cfeffb76e4cf24ac01cb4dd6697685101086e97648cb9e727c2935728ea2252935a67967fa89db3eb457c33149bd65abfb37bf71c00fe0687ac76e303cdc3f062b06ea2f38286b0bc138c9f3829426a3cd401098c66d3394a0cf45beeb78c040e956ce30c9f233bf3fdd2026b8d2ef177aa0a852445175b5ac4e7637f6d00e9ffb9aa6c4d839fdaeebf1650dee5d17d672a0f35000a5bc75cc39ca64a7ff167b66e63230a20a7079cb3227e062a7bc0d5f3d1d13dbf57ffd19a9e6e4ab51435617ff80d491b01d2695b0bbf06791c6e1a184831a7f9010b2a0d367027b56ff08232beabaae687968c2574a4074d2433f583fe0511a142c5408217f2d1c9c2b3b5f63775923f1fda22f72502046d14064bbd81d8989666a1000c19746474411286bfce6b897f3b7d322b91a4a0bb899dc09793db321b6280875b079e7b0fc0d6eaf8be3291bb37c618a70b075a704cf994c71062768cd967f986016b49d200000000070001000000000000000000000000000000000000000000000000000000000000000400000000000000ca01000000000000000000000000000000000000000000546f6b656e4272696467650100000003b0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecf"))
	// And one executed after the delay; then, bound to forked, the switch.
	at(start+5*day, "forked")
	testing.SetRealm(testing.NewCodeRealm(unpauser2))
	tokenbridge.ProposeChainID(cross(cur))
	at(start+6*day, "forked")
	testing.SetRealm(testing.NewUserRealm(user))
	tokenbridge.ExecuteChainID(cross(cur))
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole/tokenbridge/logic/v2"))
	tokenbridge.Upgrade(cross(cur), wire("01000000030d00621ae4031672f41f7598844737b2f5e722e27d4a99d2cd2cd5add00e7b0d77d0042cb9f39a37a7960fe3769d36ac03835ca1aff8040c5a8f5479d0aa8c9dfe1200011135b5763e28559acdfdccd84edc1139a79bf8bd1c62a8857bd03ac68358195802ba156d3f87716973be4b5f903868c5e180b54a909863d044d8104e9a02c7eb010232687c8e3e3f6df74f7fc2e7664f3173fb9a34422ba36ec85f8bcb92648a24ab7337b47fadbfac06f4021c113263b0b11e7fca97e1d8b7eabdc58cad016a78980103dbb3704b119254b548ef4caa1cd0a1c6a5a24204d177d2182cadcd228cf222931896861bf1bc6e83444a5bc77a9be81d3635e92e2fad7b30e7621cca05c2883e0104e93ac9ccd9f3fe90f45480507ac46ded45a1d2da1e901c7c279c028b3c32ac4569df6b86b2b9379f0473c7de5342c9511869ca62884cb7bd44a46d6491d30076010521a63e7eb1308c6ffc040b5d24f9e30eab5052b9ba49fb816cb4a286084b915734b5e9333347e9b4375635948c198081498ac1c3e45b9f74efbc869f22d55667000647ff8101da6eaa6a0791f38bbbada3ccfb25f505c20ceffce50ac254026a36874ff55b43b85b2ef575e6016ccd6865356d0974328c496c9c11ac8f9f5adadd9e010794ff816122c48ac0586d6c60e88f20368d5cd3b18e626c2243d630d6a1cd8cc965c5c2fedab65ef31ce90676eca0de48c248f105f41db7e71cf3662cb737f7e2010894c60dc8352e10757bf235cc610f41456a3a66aa66a16aa8975757fb2d3fe0e47b3bfd19e0fb8f8032a5253106ec86d00396dd83ae13d9e8c57bebe5c37e109d0109e5a4d0371d7ef641e0b02b721cff0b976d9803862185d34a5cd7c8d816d071fb38026e847509c54e04e83190b874828f87604c8998c337b2dd88ae48719b890b000aad026484f9990774d753c0a116ab9e20e2981a520ac451f4bb4beb0307eb371046de67f0433a8fcd04dcbab79595f8bda794fb0d045ff1dbfa706cbe2e6ae6fe000b39a555d4d14f9b4ed44e71cd87f39dae99aa5d59dae2d70db6ce1aab52557aa055a6c15fd78eb0195e6a00df9f36b01dfba6dd40d0a26f48b1980376d31f42fc000c86eb24f50757d76f8a3bfa10fcc708ef8a4b3d7f15aac898f8caabef443ed6df3db112da742adaa1f0a4c03ed74f28dca1cf7ff7597f229f1a5f613f5d4b0d30006b49d200000000070001000000000000000000000000000000000000000000000000000000000000000400000000000000df01000000000000000000000000000000000000000000546f6b656e42726964676502ffff00000000000000000000000092e3c23f83a6712834793c41e6faf2646ee19f26"))
	bound, pending, _ := tokenbridge.BoundChainID()
	println(tokenbridge.Logic(), bound, pending == "")
}

// Output:
// gno.land/r/wormhole/tokenbridge/logic/v2 forked true

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
//     "type": "UnpauseExpired",
//     "attrs": [
//       {
//         "key": "by",
//         "value": "g1ergv5890fm0auua4kmsqvd2hxux9u52gnfe5yj"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "Frozen",
//     "attrs": [
//       {
//         "key": "by",
//         "value": "g12ddymy2yl0u693yslxmg7c6e27qlaety5mmmrr"
//       },
//       {
//         "key": "expiry",
//         "value": "9223372036854775807"
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
//     "type": "ChainIDProposed",
//     "attrs": [
//       {
//         "key": "old",
//         "value": "dev"
//       },
//       {
//         "key": "new",
//         "value": "forked"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ChainIDProposed",
//     "attrs": [
//       {
//         "key": "old",
//         "value": "dev"
//       },
//       {
//         "key": "new",
//         "value": "forked"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ChainIDCancelled",
//     "attrs": [
//       {
//         "key": "old",
//         "value": "dev"
//       },
//       {
//         "key": "new",
//         "value": "forked"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ChainIDProposed",
//     "attrs": [
//       {
//         "key": "old",
//         "value": "dev"
//       },
//       {
//         "key": "new",
//         "value": "forked"
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
//         "value": "g1h5agk6834dxhuqae9tkjueh4pcp8uudpl0g2p2"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ChainIDCancelled",
//     "attrs": [
//       {
//         "key": "old",
//         "value": "dev"
//       },
//       {
//         "key": "new",
//         "value": "forked"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ChainIDProposed",
//     "attrs": [
//       {
//         "key": "old",
//         "value": "dev"
//       },
//       {
//         "key": "new",
//         "value": "forked"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "PeerRegistered",
//     "attrs": [
//       {
//         "key": "chain",
//         "value": "3"
//       },
//       {
//         "key": "emitter",
//         "value": "b0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecf"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ChainIDCancelled",
//     "attrs": [
//       {
//         "key": "old",
//         "value": "dev"
//       },
//       {
//         "key": "new",
//         "value": "forked"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ChainIDProposed",
//     "attrs": [
//       {
//         "key": "old",
//         "value": "dev"
//       },
//       {
//         "key": "new",
//         "value": "forked"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "ChainIDConfirmed",
//     "attrs": [
//       {
//         "key": "old",
//         "value": "dev"
//       },
//       {
//         "key": "new",
//         "value": "forked"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   },
//   {
//     "type": "LogicSwitched",
//     "attrs": [
//       {
//         "key": "old",
//         "value": "gno.land/r/wormhole/tokenbridge/logic/v1"
//       },
//       {
//         "key": "new",
//         "value": "gno.land/r/wormhole/tokenbridge/logic/v2"
//       }
//     ],
//     "pkg_path": "gno.land/r/wormhole/tokenbridge"
//   }
// ]
