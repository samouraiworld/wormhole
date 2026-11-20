// PKGPATH: gno.land/r/wormhole_test/refused
package refused

// The vault publishes before its first write, and a refused call lapses no
// proposal, so a publication Core refuses leaves nothing behind. On chain the
// refusal reverts the transaction anyway, but revive keeps a refused call's
// writes in gno test, so a write made before the publication would show here.
// Core's message fee, set to 1 by a corpus VAA and not paid, refuses each of
// the five publishing operations. The escrow, the holder's balance and the
// supply stay as they were, and so does a proposal made under another chain ID,
// which a successful call here lapses. Once Core has received its fee, the same
// 10 ugnot fund a payload-3 lock, so no refused lock moved the recorded balance
// either, and that call lapses the proposal.

import (
	"chain"
	"encoding/hex"
	"testing"
	"time"

	tb "gno.land/p/wormhole/tokenbridge/v0"
	"gno.land/r/wormhole/core"
	"gno.land/r/wormhole/tokenbridge"
)

const logic = "gno.land/r/wormhole/tokenbridge/logic/v1"

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

func main(cur realm) {
	on("dev")
	// Corpus steps: Core's fee set to 1, and RegisterChain for chain 2; then
	// the pause roles, from the vault's vectors.
	core.SubmitGovernance(cross(cur), wire("01000000030d00af8fd2044e7033ac24a027e90540351518f1023ec322a2e15a7f41d64e28b8b00f6680778adbf91e2958d78133e5dff9762fa484b16729c93d46ff9a15a29fd20001fba4671bc90f8326c402997dd90c852d90946a6d2374b7edd14ce233f982a77a5fe732b6819acd74d71e646c8175d92df35f14ecb3822ee786c77bf72b7424e70002533c88fbd2b49a60b9277dcae661d2d364e65c89e6dcac38e4736acd5436f551329a4a49317da19bcd8696139794aeef762e33a010ac674cd886d163f0a238bb010398753fd902c5725a965aaa04d4bc9b6c5a9e9425a69c39fc8330771643414f690d6b5dd9ec05d28bc93e7275cb67b019f1d6ff2371c06f307209a1ec059cea2b000491af0d4128d52bea249b951229b0a3b593d039f0fac17b73b8b23b6aedac4a6d46bce76240b59374548ecb3ef1bfa8bdba076894056d6f2312f9513740aa0e5d00058d35381319c27f5b9ca8082b546dbcd85ea667126d13ce3bea98d2f4ebabe9087a9d1569508b7db147031b2272f93bfedca287f55ab45731bf983de254c18e6e000672993b9186b30f413fd31769d7714ed308996e8551d74a493262a3d2435738ac308d6b8833ce64832dfff4e81a09dbace02aca0f7fccd35a73e518af1c8450c800071155dea96769a98bf133b5f0909cf0f86b8486427b42217c4115219d1b0d68fd15590c736ad1ab13f4e5ca091de1d492cf341603f72ade214cd023eaf7bb408d0008c6494400addc8baf8c62cb63653371a8a4c631dc9f589461feeac33c54490b43135fe268023a66590b491575d23a7984d962821da34ea8e73d274465bd865ecb0109accc10c1bc21bcab48ff58f4414279f1248fb23168e4d0dbbdccfff7ba8462017a1faf07f5ac29b612b1fc52f6a9f56f8e8edc21a540dea6f6bc0b2a4c6a210f010a5027f60452ba5844bcc88eb17cb174632a71ae872d2ba947e8a6c88f64b3d34652cca4d22316446e54420780e22bb74c18dfb134b0c01464f61f347150538010000bb7fc6f7ba25165e34c2dc33c9fe0561fd94afab6d72f778bc9d467da6edffc4a63992a766e8bbb37bb2adf262dff49c5ccb80163c8e71232f1a460989ac8e293010c48146bdeb57d52c13fc553c37134459b29b006773816da59e4f8b4d3b3f7f2f0239554b8e78235fd382b1560a955df694f0dbf6242518c5d80b2c1b2a80336ff006b49d200000000010001000000000000000000000000000000000000000000000000000000000000000400000000000000012000000000000000000000000000000000000000000000000000000000436f726503ffff0000000000000000000000000000000000000000000000000000000000000001"))
	tokenbridge.RegisterChain(cross(cur), wire("01000000030d000245f1b6fd6d2a5cf77015fe989b78a92c54f5dd086b20ba9bd5078dfa20507c5b34daecd1ac129d9d59cec27cd91dc67901911a6f96fcfca0a7f71cdf00ab8b00010fe52569de6755691d8275e5a053442b37bedbdc26383196617781762156d8524d1f45154949c43170eef302ccd5a65043a4c84814e696c285e50fb30f0d1f78000211f09cb4bdafbc9eb299c03df07fa38791e83a3f369aebafceec05351de76c087651984e77c3f39a35e971e219f4f4f681b94d242f2db000189c4ebd5a4e893a0103c4cc5156263a5da8c54f6768373f7de41d73177082cf5736d4e36b7b8f0a3f153c6af0022b6d53bbbb5aec57324f9ad12be5dddd63c0547a4b422dda2f7c9a8e0004d5329bc3204c9986c649d0bda12409730e55d7af0241666733b35465e35df02e05dcd0c11e47733ff0d2a750e38a24505ad8347eecc12d956c0b4fa5c3c5b3000105795717059344c813633fa85d0300d190906cc700c73ff538d810110c551f0a2d7cec9052d1a0e2489b5b38cbfbf20f6448adcdf5b79aec452f5c65d37d18128801064765df7ce01424e9b2a8d2d2ccdfeeb582d93742835ffde8f5674693871371303aa1c7abcc30848cdd9189731b14e25c7084324fa624c02dd71b7c8384460ecb0107da264205502aeb83dd264f0632dfd0f6d11f1fc2e96f032fb7b542748a9df11c18c8d3272249583f93d07c46dbe371741ae0dd4b82f890e3110e9dac564ad5ba0008a8bfe6e2d4902c80b745cf4c67ea2b811f0f634412a5c4fb8baa176caf9e8cd40eb38ae6459e80e389e64ccf6385c492e1ab30970688a8ffce754d85719635ae0109204806cab5e947e5508f2f7fce88dc1d10f58b5ff96033cc92676a58e0cc5b0b44ba35d0bf259da0592043ea0485925935b6f36607fde363f127edf64c624755000af9cd3116bca268f97db66e3cac4d7d4e976d5f497ba1fee25bc877d4f6d395507da92f87bed17ad240396f7f4ca6f5d5f27387149be9794a147aef626732cc8a010b4a75d8592eadb68ab48dba07a1ccbf8750a61dda96b10f6a8dc74f88fcb529b227fb110568b1fb91a77e93274e0846dad2501a1cfef1565caf65417bf4f6db44010c3b12e826a8be1b37ec530f7b23c473b8d66b6e1a59f55c3d3f66aca90aa6ffe36511e78f53f06be21bd3925a53701b261a432cb83671415d8e6829d8fc2a932b006b49d2000000000100010000000000000000000000000000000000000000000000000000000000000004000000000000000120000000000000000000000000000000000000000000546f6b656e4272696467650100000002000000000000000000000000e7000000000000000000000000000000000000b1"))
	tokenbridge.SetPauserAddresses(cross(cur), wire("01000000030d00dbf41ee2ae64f7a02643822a4a22558b80044bd48df8657fb85131ae1e7a292872ddef95fb4de8da74a33540780ab0efad78a2753019aa19d92e85fb055422a600010c4dd71f4b51870cc654c4bf4e415694612218e2732652fef78eb694b20bc6a614f305d25a0a25bd1ba914ff106e3d8555fed844683b12c0f9a9b466bd0e57370102c03865e07a9c2c4203d81b796e3f3bb3cf515e304fd81dc746dc72e96b38f94b1c6b275d8bf238af3e8bde44f6dca4d53783eb15abbbef1333dec877d414b3c1010386cabda02ac06819ed6d187aa71351871f749f9b8e5c611af8c83260858cea003313bd0c9187399683ffc4fdd124c619fd14f7c211549364a6a191573f580bc00004c30c7b57fb4009ba8bf6e483f00607c52601a1be91547b775bf775f1e039c7682eddb012b0b5c00010549e6a25eccbbca1700a0ea4557fe804d326cb3586df5600052b9c6fd67fe9c4490079832d93f05d0d73f0b7721ed78678fdea4fa0c4e1589a231284776fde3ee138193f13f2f274442fbfc43b8b5111a419deda58fcb3786400061a7a967d33f6c0c0636f5e11479c737aa01d2343d58e833101ee8d77174c1a251822ac18be715d328238642be3582ba3bd4cfab5ed86450c4c45ce3f6a8b0c2e01074e483d7b0cdd2b85e90eac30deec72ed8770f00f692571e326252d706bef84317c8d5182106e540e3159b4a860e42737d496e904c435f6eb37f8d22af9f8936f0008fb5ce93583cb808bdd7d3c7a0ad72daa74b78790af89436667d5c545fce14b8e4b82cd41ecc72b1bfea579ac21b8f795e87792afd06cdbe28fedbb25c0fe1b0c010972ff7b66fa8775b92f5a2480d62c78a9efadb50b643c8bcd350845428d18800919976ba39fffa013e03b1749cfe84c337129674d49ed2168d21292f6006dba25010aa542a6260dc12c00691b01cd9e919c440939dc982cd68039d01a4b6dfdf411b036db88871c3a9bc96963ad5e17b6c671b33dd9ff83cc5815ad6c814c3b841219000bbbd5c9502000f7abd0699b2657fe6bc4dcbdff65a63b864ee281ddc4749aa69b014fa4a25622d895ba5edd5ef8a83472efe7ca609acba846fa7fdef515bae3d2010cb5523ff8be57d0d7e75c3334d416c53bd3588897968f9de4d3307a2acd6da19c0c26ebfdd6f13ca59406131a45eaec015b07d989a6eb89a4e25bbe8371dc7f8a016b49d200000000070001000000000000000000000000000000000000000000000000000000000000000400000000000000d601000000000000000000000000000000000000000000546f6b656e42726964676504ffff14514845a71a60dad8be03ba0cfab4f7a66d4b4c4714535a4d9144fbf9a2c490f9b68f63595781fee564146e741991ca9547c4d82d3e348340a6f17d369ee0"))
	user := chain.PackageAddress("gno.land/r/wormhole_test/user")
	recipient := [32]byte{31: 0xee}
	testing.SetRealm(testing.NewCodeRealm(logic))
	usdc := tb.Origin{Chain: 2, Address: [32]byte{31: 0x0c}}
	m := tb.AssetMeta{Token: usdc, Decimals: 6}
	copy(m.Symbol[:], "USDC")
	copy(m.Name[:], "USD Coin")
	tokenbridge.CreateWrapped(cross(cur), m, [32]byte{})
	tokenbridge.Mint(cross(cur), usdc, user, 5)
	// The unpauser's proposal, made under another chain ID, is not live under
	// dev.
	on("forked")
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/unpauser"))
	tokenbridge.ProposeChainID(cross(cur))
	on("dev")
	testing.SetRealm(testing.NewCodeRealm(logic))
	testing.IssueCoins(chain.PackageAddress("gno.land/r/wormhole/tokenbridge"), chain.NewCoins(chain.NewCoin("ugnot", 10)))
	println(revive(func() { tokenbridge.LockAndPublish(cross(cur), user, 10, 2, recipient, 0, 0) }))
	println(revive(func() { tokenbridge.LockAndPublishWithPayload(cross(cur), user, 10, 2, recipient, []byte("hi"), 0) }))
	println(revive(func() { tokenbridge.BurnAndPublish(cross(cur), usdc, user, 5, 2, recipient, 0, 0) }))
	println(revive(func() {
		tokenbridge.BurnAndPublishWithPayload(cross(cur), usdc, user, 5, 2, recipient, []byte("hi"), 0)
	}))
	println(revive(func() { tokenbridge.PublishGNOTMeta(cross(cur), 0) }))
	_, pending, _ := tokenbridge.BoundChainID()
	println(tokenbridge.LockedGNOT(), tokenbridge.BalanceOf("USDC", user), tokenbridge.TotalSupply("USDC"), pending)
	testing.IssueCoins(chain.PackageAddress("gno.land/r/wormhole/core"), chain.NewCoins(chain.NewCoin("ugnot", 1)))
	seq := tokenbridge.LockAndPublishWithPayload(cross(cur), user, 10, 2, recipient, []byte("hi"), 0)
	_, pending, _ = tokenbridge.BoundChainID()
	println(seq, tokenbridge.LockedGNOT(), pending == "")
}

// Output:
// core: fee-unpaid
// core: fee-unpaid
// core: fee-unpaid
// core: fee-unpaid
// core: fee-unpaid
// 0 5 5 forked
// 0 10 true
