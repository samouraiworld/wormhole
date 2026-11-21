// PKGPATH: gno.land/r/wormhole_test/outboundcallers
package outboundcallers

// Who may send out, and the order of the outbound checks, where
// revive can show them: before the origin-call guard, or for a realm sender,
// which never reaches it. The gate comes first, under a pause and under the
// chain-ID freeze, for every outbound entry point and arguments it never
// reads, and before the origin-call guard of a user's AttestGNOT, whose realm
// path reaches the vault's own gate. GNOT leaves only on a direct user call: a realm, a realm through
// tbsender, an alias in tbalias called from a realm, and a maketx run script
// all fail with deposit-not-user-call, and a user's call from inside revive,
// which the test runtime does not count as the origin call, fails the guard
// that stands for a nested or aliased one. A realm sender's wrapped transfer
// takes each of its checks in order, and a refused one burns, publishes and
// counts nothing. A wrapped asset the allowlist does not list cannot go out.
// What the origin call attached is never read for a realm sender.

import (
	"chain"
	"chain/runtime"
	"encoding/hex"
	"testing"
	"time"

	tb "gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/core"
	"gno.land/r/wormhole/tokenbridge"
	v1 "gno.land/r/wormhole/tokenbridge/logic/v1"
	"gno.land/r/wormhole_test/tbalias"
	"gno.land/r/wormhole_test/tbsender"
)

const (
	logicPath = "gno.land/r/wormhole/tokenbridge/logic/v1"
	usdc      = "000000000000000000000000a000000000000000000000000000000000000048"
)

var recipient = [32]byte{31: 0xee}

func wire(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return b
}

func on(chainID string) {
	ctx := testing.GetContext()
	ctx.Time = time.Unix(1_800_000_000, 0)
	ctx.ChainID = chainID
	testing.SetContext(ctx)
}

// sent prints what a refused transfer must leave: the vault's next sequence,
// the escrow, the sender's USDC, its supply, and what USDC's window counted.
func sent(sender address) {
	_, _, _, out, _, _ := v1.Limits(2, usdc)
	println(core.NextSequence(vaultEmitter()), tokenbridge.LockedGNOT(), tokenbridge.BalanceOf("USDC", sender),
		tokenbridge.TotalSupply("USDC"), out)
}

// vaultEmitter is the vault's address, left-padded: the bridge's emitter.
func vaultEmitter() [32]byte {
	var e [32]byte
	copy(e[12:], wire("ec284bb840cb6b26cedd71e45561c6c09d2c42d3"))
	return e
}

// entries calls every outbound entry point with arguments it never reads.
func entries(cur realm) {
	println(revive(func() { v1.TransferGNOT(cross(cur), 0, 0, [32]byte{}, -1, 0) }))
	println(revive(func() { v1.TransferGNOTWithPayload(cross(cur), 0, 0, [32]byte{}, nil, 0) }))
	println(revive(func() { v1.TransferWrapped(cross(cur), "NONE", 0, 0, [32]byte{}, -1, 0) }))
	println(revive(func() { v1.TransferWrappedWithPayload(cross(cur), "NONE", 0, 0, [32]byte{}, nil, 0) }))
	println(revive(func() { v1.AttestGNOT(cross(cur), 0) }))
}

func main(cur realm) {
	on("dev")
	user := chain.PackageAddress("gno.land/r/wormhole_test/user")
	sender := chain.PackageAddress("gno.land/r/wormhole_test/tbsender")
	tokenbridge.RegisterChain(cross(cur), wire("01000000030d00702242a4cbc01e3c80ec68af614c764bdbaa92217be40fc30ac79258ac38599c416c05982b2926dee53f12ec7f88e89cc00e73d669e49fe4a4b0e1b5104ef1700001cacb1e94ac2c109f57d82e1401c22b72cf82fd7492513684c45f90935255ee992325f364d52283b6698d233bcba28e9b255a88a0ded1bd554060a56ead01cb8f000297f4d3f152ddc1c1a86da86b515d1207f89844de2335b42693660322308f7ec91362f13ec12f374972d6ec6f24c3b79c72c1ed7eb0bff4481823cd39d3d1a383010395236c4fe5481a78a0b6881e3003aa175503e0dc7e61fe28e3708da726c4559b1778cc60e4e5598eca27c2907f8e6d3cf93a317edec601c4d6a8e4caae149ed00104a4938eee1603b563158eaf7efa3d4567ade9a61aee36f7aae50de8d6ea76b2f0179d8494b00b3ad2747166ac1bf4f11af95b1956bcb076ad057aea0fc98f13a500057ec86196b6b8bf154c27bde55ef02ccc6957571bafcf57515c112856e71d84255002548480db3f46fb9f6e12aca44287618ff31b3947ba413b64d96fe602daad0006efb7ff1394a7672908e5fc1e36ba19534b5db80cffe6803593a12fc51b84440e4e52a0622d381269abb63c411174f4f4fa9d4f5aded3750f0a87a51e9deeeeac01070730771bcf1d356247cfa25d58066e36a03cb387d091277e2ad1eb20ad1645d8091ed6b41166c6fcb73db1373f630fe6e8b6bd479be01e35952a9741e94b72b00108d4e806b0bfbaf8130366386f3be3c7d4a6ccd53fcc88342219a6597001a47bba3360ac7ecba68f14ef19e06adb8a98b404badbfcb01c17ce83c4195011fb89880109f4159a6c9195e0a5c06ca12c5e6a2706e5e765a87f1d5691bc858def80f3c0fb675311efa19f8a3dce3f9889de16731ef4f0899c4e75aa72d7a8d2a7be303e94010a8f96de37f9269664cde3d2271471703415f8147bacc8f82fdac786817e47a442356e2368d953024049243db9032f22b0d8c6659dd30942faafb157b0f3c97452010b66ede326db9247cdc1cb72b99193fe2f9791c80e1d0c34ac2c4ad2a59b8c50404784a48a756f8111da8a760bfed83d7af681c6f569d44196243b014b02daa4ff000c0eaea9e5bf052c23b52f19a77711da2d8f5c352bae8b556290d9f40a862a465f44c5438527b4b6d99a97b201700277984e8989ec7dba41e7ded5ceb4b693cd36006b49d200000000070001000000000000000000000000000000000000000000000000000000000000000400000000000000c901000000000000000000000000000000000000000000546f6b656e42726964676501ffff0002a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf"))
	tokenbridge.SetPauserAddresses(cross(cur), wire("01000000030d00dbf41ee2ae64f7a02643822a4a22558b80044bd48df8657fb85131ae1e7a292872ddef95fb4de8da74a33540780ab0efad78a2753019aa19d92e85fb055422a600010c4dd71f4b51870cc654c4bf4e415694612218e2732652fef78eb694b20bc6a614f305d25a0a25bd1ba914ff106e3d8555fed844683b12c0f9a9b466bd0e57370102c03865e07a9c2c4203d81b796e3f3bb3cf515e304fd81dc746dc72e96b38f94b1c6b275d8bf238af3e8bde44f6dca4d53783eb15abbbef1333dec877d414b3c1010386cabda02ac06819ed6d187aa71351871f749f9b8e5c611af8c83260858cea003313bd0c9187399683ffc4fdd124c619fd14f7c211549364a6a191573f580bc00004c30c7b57fb4009ba8bf6e483f00607c52601a1be91547b775bf775f1e039c7682eddb012b0b5c00010549e6a25eccbbca1700a0ea4557fe804d326cb3586df5600052b9c6fd67fe9c4490079832d93f05d0d73f0b7721ed78678fdea4fa0c4e1589a231284776fde3ee138193f13f2f274442fbfc43b8b5111a419deda58fcb3786400061a7a967d33f6c0c0636f5e11479c737aa01d2343d58e833101ee8d77174c1a251822ac18be715d328238642be3582ba3bd4cfab5ed86450c4c45ce3f6a8b0c2e01074e483d7b0cdd2b85e90eac30deec72ed8770f00f692571e326252d706bef84317c8d5182106e540e3159b4a860e42737d496e904c435f6eb37f8d22af9f8936f0008fb5ce93583cb808bdd7d3c7a0ad72daa74b78790af89436667d5c545fce14b8e4b82cd41ecc72b1bfea579ac21b8f795e87792afd06cdbe28fedbb25c0fe1b0c010972ff7b66fa8775b92f5a2480d62c78a9efadb50b643c8bcd350845428d18800919976ba39fffa013e03b1749cfe84c337129674d49ed2168d21292f6006dba25010aa542a6260dc12c00691b01cd9e919c440939dc982cd68039d01a4b6dfdf411b036db88871c3a9bc96963ad5e17b6c671b33dd9ff83cc5815ad6c814c3b841219000bbbd5c9502000f7abd0699b2657fe6bc4dcbdff65a63b864ee281ddc4749aa69b014fa4a25622d895ba5edd5ef8a83472efe7ca609acba846fa7fdef515bae3d2010cb5523ff8be57d0d7e75c3334d416c53bd3588897968f9de4d3307a2acd6da19c0c26ebfdd6f13ca59406131a45eaec015b07d989a6eb89a4e25bbe8371dc7f8a016b49d200000000070001000000000000000000000000000000000000000000000000000000000000000400000000000000d601000000000000000000000000000000000000000000546f6b656e42726964676504ffff14514845a71a60dad8be03ba0cfab4f7a66d4b4c4714535a4d9144fbf9a2c490f9b68f63595781fee564146e741991ca9547c4d82d3e348340a6f17d369ee0"))
	v1.CreateWrapped(cross(cur), wire("01000000030d003b9fd5af401029670f9d7a47d876ece2c38347c080d819d4538fe5ca72fd65c201169d37c99afb5d99a66e6d285ddd60676c643337818dc7e12d1758e34aa2be0101da9ecd659914567e82be5f64d34659d5dade852aaeaee81bdf27270fc1faf99c12b78afeb2001278ba387fcd467c6a2ad62c8b089f4974f19f289a34636ab27900027eddf1604c34c3d0bfaf8b0274a0418c3b890ec07fc17ef94af08814b5d513db798ba583b8faa86c15477d804a3544014afe32af93998fcc865102c2ef79b0430103e9d472de5c810491f92100c87eeeebc1bafb91cbd0a6162c4498e4a6914c937b4e2b3de3436b5f440c0b8696f72eec0161560f8f0138785e1d711973c797c6400004267319deaf215262713c082f127ce686f0f2df275c2068b9f497fa44c8d8a7a07cee40a8fa3c51a405f364c5a7ef1d2e5ebd32dccd2a8800a905528e7ded6ff1010516ecf6e00300ff5a1a41b4888c5a4b2a83be44589ecf8f923964dbb47308c0b314583f70a01dddadaf36abd89a099e5a60ef2717304b18de19fae581fe119b2a0106f5e4af8b355ac44cbbcb2d97c27b55291e7c6b26d3560e670356f1d9a2cacc601ffe1d31f632343b2d3ea0aa5ff31bb6e9d9a3f1bed6893e106e6b3b21de089f00076aca12d74da2541ebba4c593f3d4b88b1a2f8ec3b01b7225f30824efb86a52a06c29369fb421e8004eeaaed4598156b1a657393a7df5c91c60b772fb17e9df8800085559efe593c2a495711ff0837d18bba7333b174beb062c464f26b8b569c4ff106d82b7b927acf151a290747452bb6f93a7a76468beac151ea42eca66b957bb00000907ae424e7524a3dc1e77e9349cba39849df55f02118564af1152991f5a8abc1f4bb22eb06a239ac29dc6ba77458148284f686b25595849f88b108640df26a2f6010afbaa29cf7aee6f554d509d6dbda7491004769233355fbf317f8a3abc5171f42618675ddf5d8aa4aa3191967f38c6662eb95f5aadb39e582013b3eb7fe5bed09e000b5cff4b149f1917d0f3db16c345b68124061ee83f66f2101448f6abc34e29aa115fb93ab6cf40441e6291c68b512bbfc9c915a193b922134991d84773057d5cb6000c493c629fbcdfdecf3eed4075e4470682cf801c9b5126157e07be2a76cef7180d24f4c37f44c4bf34ebb94f374ab6e003a9144a43f1a342ae76396124c940c932016b49d200000000070002a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf00000000000000010102000000000000000000000000a000000000000000000000000000000000000048000206555344430000000000000000000000000000000000000000000000000000000055534420436f696e000000000000000000000000000000000000000000000000"))
	// A wrapper the logic does not list, which the vault creates on its word.
	weth := tb.AssetMeta{Token: tb.Origin{Chain: 2, Address: [32]byte{12: 0xc0, 31: 0x02}}, Decimals: 6}
	copy(weth.Symbol[:], "WETH")
	copy(weth.Name[:], "Wrapped Ether")
	testing.SetRealm(testing.NewCodeRealm(logicPath))
	tokenbridge.CreateWrapped(cross(cur), weth, [32]byte{})
	tokenbridge.Mint(cross(cur), weth.Token, sender, 10)
	tokenbridge.Mint(cross(cur), tb.Origin{Chain: 2, Address: [32]byte{12: 0xa0, 31: 0x48}}, sender, 1000)

	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/pauser"))
	tokenbridge.Pause(cross(cur))
	println("paused")
	entries(cur)
	testing.SetRealm(testing.NewUserRealm(user))
	println(revive(func() { v1.AttestGNOT(cross(cur), 0) }))
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/unpauser"))
	tokenbridge.Unpause(cross(cur))
	on("forked")
	println("frozen")
	entries(cur)
	testing.SetRealm(testing.NewUserRealm(user))
	println(revive(func() { v1.AttestGNOT(cross(cur), 0) }))
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/unpauser"))
	on("dev")

	println("GNOT from anyone but a direct user")
	println(revive(func() { v1.TransferGNOT(cross(cur), 10, 2, recipient, 0, 0) }))
	println(revive(func() { v1.TransferGNOTWithPayload(cross(cur), 10, 2, recipient, nil, 0) }))
	println(revive(func() { tbsender.SendGNOT(cross(cur), 10, 2, recipient) }))
	println(revive(func() { tbalias.X(cross(cur), 10, 2, recipient, 0, 0) }))
	testing.SetRealm(runtime.NewRealm(user, "gno.land/e/"+string(user)+"/run"))
	println(revive(func() { v1.TransferGNOT(cross(cur), 10, 2, recipient, 0, 0) }))
	testing.SetRealm(testing.NewUserRealm(user))
	println(revive(func() { v1.TransferGNOT(cross(cur), 10, 2, recipient, 0, 0) }))
	println(revive(func() { v1.TransferGNOTWithPayload(cross(cur), 10, 2, recipient, nil, 0) }))
	println(revive(func() { v1.TransferWrapped(cross(cur), "USDC", 10, 2, recipient, 0, 0) }))
	println(revive(func() { v1.TransferWrappedWithPayload(cross(cur), "USDC", 10, 2, recipient, nil, 0) }))
	println(revive(func() { v1.AttestGNOT(cross(cur), 0) }))
	sent(sender)

	println("a realm sender's checks, in order")
	println(revive(func() { tbsender.SendWrapped(cross(cur), "NONE", 0, 3, recipient, -1) }))
	println(revive(func() { tbsender.SendWrapped(cross(cur), "USDC", 0, 3, recipient, -1) }))
	println(revive(func() { tbsender.SendWrapped(cross(cur), "USDC", 10, 3, recipient, -1) }))
	println(revive(func() { tbsender.SendWrapped(cross(cur), "USDC", 10, 2, recipient, -1) }))
	println(revive(func() { tbsender.SendWrapped(cross(cur), "USDC", 10, 2, recipient, 11) }))
	println(revive(func() { tbsender.SendWrapped(cross(cur), "USDC", 1001, 2, recipient, 0) }))
	println(revive(func() {
		tbsender.SendWrappedWithPayload(cross(cur), "USDC", 10, 3, recipient, make([]byte, 1916))
	}))
	println(revive(func() {
		tbsender.SendWrappedWithPayload(cross(cur), "USDC", 10, 2, recipient, make([]byte, 1916))
	}))
	println(revive(func() { tbsender.SendWrapped(cross(cur), "WETH", 10, 2, recipient, 0) }))
	println(revive(func() { tbsender.SendWrappedWithPayload(cross(cur), "WETH", 10, 2, recipient, nil) }))
	sent(sender)

	println("a realm sender's transfer, whatever the origin call attached")
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 7), chain.NewCoin("foo", 1)))
	println(tbsender.SendWrapped(cross(cur), "USDC", 10, 2, recipient, 10))
	println(tbsender.SendWrappedWithPayload(cross(cur), "USDC", 20, 2, recipient, make([]byte, 1915)))
	println(tbsender.Attest(cross(cur)))
	sent(sender)
}

// Output:
// paused
// tokenbridge: bridge-paused
// tokenbridge: bridge-paused
// tokenbridge: bridge-paused
// tokenbridge: bridge-paused
// tokenbridge: bridge-paused
// tokenbridge: bridge-paused
// frozen
// tokenbridge: bridge-frozen
// tokenbridge: bridge-frozen
// tokenbridge: bridge-frozen
// tokenbridge: bridge-frozen
// tokenbridge: bridge-frozen
// tokenbridge: bridge-frozen
// GNOT from anyone but a direct user
// tokenbridge: deposit-not-user-call
// tokenbridge: deposit-not-user-call
// tokenbridge: deposit-not-user-call
// tokenbridge: deposit-not-user-call
// tokenbridge: deposit-not-user-call
// invalid non-origin call
// invalid non-origin call
// invalid non-origin call
// invalid non-origin call
// invalid non-origin call
// 0 0 1000 1000 0
// a realm sender's checks, in order
// tokenbridge: wrapped-not-found
// tokenbridge: zero-amount
// tokenbridge: unregistered-target
// tokenbridge: amount-out-of-range
// tokenbridge: fee-exceeds-amount
// tokenbridge: burn-exceeds-balance
// tokenbridge: unregistered-target
// tokenbridge: payload-too-large
// tokenbridge: not-allowlisted
// tokenbridge: not-allowlisted
// 0 0 1000 1000 0
// a realm sender's transfer, whatever the origin call attached
// 0
// 1
// 2
// 3 0 970 970 30
