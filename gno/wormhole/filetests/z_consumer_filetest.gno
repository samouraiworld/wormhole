// PKGPATH: gno.land/r/wormhole_test/consumer
package consumer

// A consumer realm keeps what VerifyVAA returns and may modify it: the struct
// and its arrays are copies it owns. Payload aliases raw, which this realm
// allocated, so it is this realm's too; a consumer copies what it keeps. The
// VAA is scenario quorum-13-of-19, step 0, of the Core test corpus
// (gno/testdata/core-vectors.json).

import (
	"encoding/hex"

	"gno.land/p/wormhole/vaa/v0"
	"gno.land/r/wormhole/core"
)

const wire = "01000000030d006f699d8cd5d72de4f6f3c954086209a0199c7b620c49f5ac0ce729a87057fb4160016a1ab3c5eda721a67e747e4bdab56b7b05d6051ce885b9d29d16973ae6310101576c6da70a20af072fdc9aaeb5dd33474ec965d26fefe8e2a925369b497019d112ea1088d4e7cf5e728e80389688d137b2490b6394d61f7c4c3166bc4c47649e0002a60b47d784d368c5e3e984e410da745ca04a8f4518f9df819b7ee69c81095eeb4cc1c6aed349b0d29a0ea426d93b3d1b9a26cdabf3c86331e024065c3e9a6f4801034dd531328f11cc9d3747b769a129ed1009a8cfc967f2cf20bc670a01c4420acb012e9c928975e410a1ff05429d62819df3dfe0931714615aae23a98b93812ee50004ed028fe9603ff85823a4745d2e1618cdb154275c0ba9d9f626aa4a8b2584ac0f2fef78da0a74fc7a25115fae6769ed9289fe3d47e24af7b56ab751ed9f18bef20005cebbebeb08867469a97c8ecd3eeb017dbbfa7a1945efafcd000e0f38fbb4d2bd337573d75432b8b1055b2ce66563256b13dfbd8e13723178a6c17fb8c1feeabf0006d38d8c5f30d356ec35828535e1cdbadb92beaac945f96ce450d30aefc1e869ec2df9b9ef3f224a336f731703d55d37411e3b7513dd1ae3968e249b4194c7925301070285e457eb8d6ee1be03b129ed94dc840709912bfa7240c3d4f1f65486d5f6c239dc845e10342d4423bf5625f689796c834e3a72ec028f31d4e523e09ccbfbad00089605d102d410ba6d2e7f0ade7f1d39b37555a100d443c1c0df8b269dbd060677195f6dfd4e273f9fef5fcc68db76a135f901e92df728c763f274420127abef5101095299da1957b52b6039e0748021f5f9402add70821219b38289e5a646fc6704313ef240cb5d43baf92e4dff8ffd8df5096e3b7a55c18f1ed0ec56d439cec68e00000a70ddbaa517927fdb17fd0711a9f9c4e48d73f0c9304a2013f8d073d41f636c1500b0427e1d1261127aeabb5ae9e7cbab688e0ce946519994014491e06c8b1d61000b18644239d4369b7f3d6bd917ec13cda59a9b6172be5aacce41f42a44638d116576612419dadb2d8262574e19766b130586ba9f11ce51abc21da9f12f30f4c0ea010cf7e7571a0e30cdbf6baebff1b50e349caca3d4a6815c99afca0d09a1d803fb5f6cba2d23d547d8c71e829eb6552430fec2d60f688780d848614ae242eb4ef024016b49d2000000000700020000000000000000000000000000000000000000000000000000000000000042000000000000000101676e6f2d776f726d686f6c6520636f726520766563746f72"

var (
	kept    vaa.VAA
	payload []byte
)

func main(cur realm) {
	raw, err := hex.DecodeString(wire)
	if err != nil {
		panic(err)
	}
	kept = core.VerifyVAA(raw)
	payload = append([]byte(nil), kept.Payload...)
	kept.Sequence++
	kept.Digest[0] ^= 0xff
	kept.EmitterAddress[31] = 0
	payload[0] = 'G'
	kept.Payload[0] = 'X'
	println(kept.GuardianSetIndex, kept.EmitterChain, kept.Sequence, kept.EmitterAddress[31], string(payload))
	println(string(raw[len(raw)-len(kept.Payload):]))
	println(core.CurrentGuardianSetIndex())
}

// Output:
// 3 2 2 0 Gno-wormhole core vector
// Xno-wormhole core vector
// 3
