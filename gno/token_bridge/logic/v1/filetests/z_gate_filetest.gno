// PKGPATH: gno.land/r/wormhole_test/logicgate
package logicgate

// The logic's gate. While paused, Redeem, CreateWrapped and
// CompleteClaim refuse with bridge-paused before they read their arguments,
// and under the chain-ID freeze with bridge-frozen; a pause is checked first.
// Activate applies no gate: while paused the vault's Upgrade reaches its
// governance checks, and only under the freeze does Upgrade refuse it. The
// reads apply no gate either. The gate comes before the vault's caller check,
// so a logic that was replaced says not-current-logic only while the bridge
// runs.

import (
	"encoding/hex"
	"testing"
	"time"

	"gno.land/r/wormhole/tokenbridge"
	v1 "gno.land/r/wormhole/tokenbridge/logic/v1"
	v2 "gno.land/r/wormhole/tokenbridge/logic/v2"
)

const usdc = "000000000000000000000000a000000000000000000000000000000000000048"

func wire(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return b
}

// on sets the runtime chain ID, at the corpus's block time.
func on(chainID string) {
	ctx := testing.GetContext()
	ctx.Time = time.Unix(1_800_000_000, 0)
	ctx.ChainID = chainID
	testing.SetContext(ctx)
}

// entries calls each gated entry point with arguments that fail if it reads
// them, then Activate.
func entries(cur realm) {
	garbage := []byte("garbage")
	println(revive(func() { v1.Redeem(cross(cur), garbage) }))
	println(revive(func() { v1.CreateWrapped(cross(cur), garbage) }))
	println(revive(func() { v1.CompleteClaim(cross(cur), 2, [32]byte{}, 1, garbage) }))
	println(revive(func() { v2.Activate(cross(cur), garbage) }))
}

func main(cur realm) {
	on("dev")
	tokenbridge.SetPauserAddresses(cross(cur), wire("01000000030d00dbf41ee2ae64f7a02643822a4a22558b80044bd48df8657fb85131ae1e7a292872ddef95fb4de8da74a33540780ab0efad78a2753019aa19d92e85fb055422a600010c4dd71f4b51870cc654c4bf4e415694612218e2732652fef78eb694b20bc6a614f305d25a0a25bd1ba914ff106e3d8555fed844683b12c0f9a9b466bd0e57370102c03865e07a9c2c4203d81b796e3f3bb3cf515e304fd81dc746dc72e96b38f94b1c6b275d8bf238af3e8bde44f6dca4d53783eb15abbbef1333dec877d414b3c1010386cabda02ac06819ed6d187aa71351871f749f9b8e5c611af8c83260858cea003313bd0c9187399683ffc4fdd124c619fd14f7c211549364a6a191573f580bc00004c30c7b57fb4009ba8bf6e483f00607c52601a1be91547b775bf775f1e039c7682eddb012b0b5c00010549e6a25eccbbca1700a0ea4557fe804d326cb3586df5600052b9c6fd67fe9c4490079832d93f05d0d73f0b7721ed78678fdea4fa0c4e1589a231284776fde3ee138193f13f2f274442fbfc43b8b5111a419deda58fcb3786400061a7a967d33f6c0c0636f5e11479c737aa01d2343d58e833101ee8d77174c1a251822ac18be715d328238642be3582ba3bd4cfab5ed86450c4c45ce3f6a8b0c2e01074e483d7b0cdd2b85e90eac30deec72ed8770f00f692571e326252d706bef84317c8d5182106e540e3159b4a860e42737d496e904c435f6eb37f8d22af9f8936f0008fb5ce93583cb808bdd7d3c7a0ad72daa74b78790af89436667d5c545fce14b8e4b82cd41ecc72b1bfea579ac21b8f795e87792afd06cdbe28fedbb25c0fe1b0c010972ff7b66fa8775b92f5a2480d62c78a9efadb50b643c8bcd350845428d18800919976ba39fffa013e03b1749cfe84c337129674d49ed2168d21292f6006dba25010aa542a6260dc12c00691b01cd9e919c440939dc982cd68039d01a4b6dfdf411b036db88871c3a9bc96963ad5e17b6c671b33dd9ff83cc5815ad6c814c3b841219000bbbd5c9502000f7abd0699b2657fe6bc4dcbdff65a63b864ee281ddc4749aa69b014fa4a25622d895ba5edd5ef8a83472efe7ca609acba846fa7fdef515bae3d2010cb5523ff8be57d0d7e75c3334d416c53bd3588897968f9de4d3307a2acd6da19c0c26ebfdd6f13ca59406131a45eaec015b07d989a6eb89a4e25bbe8371dc7f8a016b49d200000000070001000000000000000000000000000000000000000000000000000000000000000400000000000000d601000000000000000000000000000000000000000000546f6b656e42726964676504ffff14514845a71a60dad8be03ba0cfab4f7a66d4b4c4714535a4d9144fbf9a2c490f9b68f63595781fee564146e741991ca9547c4d82d3e348340a6f17d369ee0"))
	println("running")
	entries(cur)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/pauser"))
	tokenbridge.Pause(cross(cur))
	println("paused")
	entries(cur)
	println(v1.Allowlisted(2, usdc), len(v1.Render("")) > 0)
	on("forked")
	println("paused and frozen")
	entries(cur)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/unpauser"))
	tokenbridge.Unpause(cross(cur))
	println("frozen")
	entries(cur)
	println(v1.Allowlisted(2, usdc), len(v1.Render("")) > 0)
	on("dev")
	v2.Activate(cross(cur), wire("01000000030d00621ae4031672f41f7598844737b2f5e722e27d4a99d2cd2cd5add00e7b0d77d0042cb9f39a37a7960fe3769d36ac03835ca1aff8040c5a8f5479d0aa8c9dfe1200011135b5763e28559acdfdccd84edc1139a79bf8bd1c62a8857bd03ac68358195802ba156d3f87716973be4b5f903868c5e180b54a909863d044d8104e9a02c7eb010232687c8e3e3f6df74f7fc2e7664f3173fb9a34422ba36ec85f8bcb92648a24ab7337b47fadbfac06f4021c113263b0b11e7fca97e1d8b7eabdc58cad016a78980103dbb3704b119254b548ef4caa1cd0a1c6a5a24204d177d2182cadcd228cf222931896861bf1bc6e83444a5bc77a9be81d3635e92e2fad7b30e7621cca05c2883e0104e93ac9ccd9f3fe90f45480507ac46ded45a1d2da1e901c7c279c028b3c32ac4569df6b86b2b9379f0473c7de5342c9511869ca62884cb7bd44a46d6491d30076010521a63e7eb1308c6ffc040b5d24f9e30eab5052b9ba49fb816cb4a286084b915734b5e9333347e9b4375635948c198081498ac1c3e45b9f74efbc869f22d55667000647ff8101da6eaa6a0791f38bbbada3ccfb25f505c20ceffce50ac254026a36874ff55b43b85b2ef575e6016ccd6865356d0974328c496c9c11ac8f9f5adadd9e010794ff816122c48ac0586d6c60e88f20368d5cd3b18e626c2243d630d6a1cd8cc965c5c2fedab65ef31ce90676eca0de48c248f105f41db7e71cf3662cb737f7e2010894c60dc8352e10757bf235cc610f41456a3a66aa66a16aa8975757fb2d3fe0e47b3bfd19e0fb8f8032a5253106ec86d00396dd83ae13d9e8c57bebe5c37e109d0109e5a4d0371d7ef641e0b02b721cff0b976d9803862185d34a5cd7c8d816d071fb38026e847509c54e04e83190b874828f87604c8998c337b2dd88ae48719b890b000aad026484f9990774d753c0a116ab9e20e2981a520ac451f4bb4beb0307eb371046de67f0433a8fcd04dcbab79595f8bda794fb0d045ff1dbfa706cbe2e6ae6fe000b39a555d4d14f9b4ed44e71cd87f39dae99aa5d59dae2d70db6ce1aab52557aa055a6c15fd78eb0195e6a00df9f36b01dfba6dd40d0a26f48b1980376d31f42fc000c86eb24f50757d76f8a3bfa10fcc708ef8a4b3d7f15aac898f8caabef443ed6df3db112da742adaa1f0a4c03ed74f28dca1cf7ff7597f229f1a5f613f5d4b0d30006b49d200000000070001000000000000000000000000000000000000000000000000000000000000000400000000000000df01000000000000000000000000000000000000000000546f6b656e42726964676502ffff00000000000000000000000092e3c23f83a6712834793c41e6faf2646ee19f26"))
	println("replaced")
	println(revive(func() { v1.CompleteClaim(cross(cur), 2, [32]byte{}, 1, nil) }))
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/pauser"))
	tokenbridge.Pause(cross(cur))
	println(revive(func() { v1.CompleteClaim(cross(cur), 2, [32]byte{}, 1, nil) }))
}

// Output:
// running
// core: malformed
// core: malformed
// tokenbridge: claim-not-found
// core: malformed
// paused
// tokenbridge: bridge-paused
// tokenbridge: bridge-paused
// tokenbridge: bridge-paused
// core: malformed
// true true
// paused and frozen
// tokenbridge: bridge-paused
// tokenbridge: bridge-paused
// tokenbridge: bridge-paused
// tokenbridge: bridge-frozen
// frozen
// tokenbridge: bridge-frozen
// tokenbridge: bridge-frozen
// tokenbridge: bridge-frozen
// tokenbridge: bridge-frozen
// true true
// replaced
// tokenbridge: not-current-logic
// tokenbridge: bridge-paused
