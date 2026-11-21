package tokenbridge

import (
	"strings"
	"testing"
)

// self is gno's Wormhole chain ID in these tests, the corpus's placeholder.
const self = 65535

// gov returns a token bridge governance payload: the module, action, target
// chain, then body.
func gov(action uint8, target uint16, body ...byte) []byte {
	p := append([]byte(module), action, byte(target>>8), byte(target))
	return append(p, body...)
}

// otherModule returns p with its module replaced by the NFT bridge's
// (ethereum/contracts/nft/NFTBridgeGovernance.sol), whose UpgradeContract
// has the token bridge's layout and governance emitter, so only the module
// tells them apart.
func otherModule(p []byte) []byte {
	q := append([]byte(nil), p...)
	copy(q[:32], strings.Repeat("\x00", 23)+"NFTBridge")
	return q
}

func emitterBytes(b byte) []byte {
	e := make([]byte, 32)
	e[31] = b
	return e
}

func TestModule(t *testing.T) {
	if len(module) != 32 || module[21:] != "TokenBridge" || module[:21] != strings.Repeat("\x00", 21) {
		t.Errorf("module = %x", module)
	}
}

func TestParseRegisterChain(t *testing.T) {
	register := func(target, chain uint16, emitter []byte) []byte {
		return gov(ActionRegisterChain, target, append([]byte{byte(chain >> 8), byte(chain)}, emitter...)...)
	}
	for _, target := range []uint16{0, self} {
		chain, emitter, err := ParseRegisterChain(register(target, 2, emitterBytes(7)), self)
		if err != nil || chain != 2 || emitter[31] != 7 || hexOf(emitter[:31]) != zeros(31) {
			t.Errorf("target %d: %d, %x, %v", target, chain, emitter, err)
		}
	}
	valid := register(0, 2, emitterBytes(7))
	wrongModule := append([]byte(nil), valid...)
	wrongModule[0] = 1
	lastModuleByte := append([]byte(nil), valid...)
	lastModuleByte[31] = 'X'
	moduleAndAction := gov(ActionUpgradeContract, 0, valid[35:]...)
	moduleAndAction[0] = 1
	for _, c := range []struct {
		name, want string
		p          []byte
	}{
		{"empty", "governance-malformed", nil},
		{"32 bytes", "governance-malformed", valid[:32]},
		{"a module byte", "governance-wrong-module", wrongModule},
		{"the module's last byte", "governance-wrong-module", lastModuleByte},
		{"the module before the action", "governance-wrong-module", moduleAndAction},
		{"action 2", "governance-unsupported-action", gov(ActionUpgradeContract, 0, valid[35:]...)},
		{"action 3", "governance-unsupported-action", gov(3, 0, valid[35:]...)},
		{"action 4", "governance-unsupported-action", gov(ActionSetPauserAddresses, 0, valid[35:]...)},
		{"the action before the length", "governance-unsupported-action", gov(ActionUpgradeContract, 0)},
		{"33 bytes, another action", "governance-unsupported-action", gov(ActionUpgradeContract, 0)[:33]},
		{"33 bytes", "governance-malformed", valid[:33]},
		{"68 bytes", "governance-malformed", valid[:68]},
		{"70 bytes", "governance-malformed", append(append([]byte(nil), valid...), 0)},
		{"the length before the target", "governance-malformed", register(3, 2, emitterBytes(7))[:68]},
		{"another target", "governance-wrong-target-chain", register(3, 2, emitterBytes(7))},
		{"the target before the chain", "governance-wrong-target-chain", register(3, 0, emitterBytes(0))},
		{"chain 0", "register-invalid-chain", register(0, 0, emitterBytes(7))},
		{"gno's own chain", "register-invalid-chain", register(0, self, emitterBytes(7))},
		{"the chain before the emitter", "register-invalid-chain", register(0, 0, emitterBytes(0))},
		{"a zero emitter", "register-zero-emitter", register(0, 2, emitterBytes(0))},
	} {
		chain, emitter, err := ParseRegisterChain(c.p, self)
		if code(err) != c.want || chain != 0 || emitter != ([32]byte{}) {
			t.Errorf("%s: %d, %x, %q; want %q", c.name, chain, emitter, code(err), c.want)
		}
	}
}

func TestParseUpgrade(t *testing.T) {
	contract := emitterBytes(9)
	got, err := ParseUpgrade(gov(ActionUpgradeContract, self, contract...), self)
	if err != nil || got[31] != 9 {
		t.Errorf("ParseUpgrade = %x, %v", got, err)
	}
	valid := gov(ActionUpgradeContract, self, contract...)
	for _, c := range []struct {
		name, want string
		p          []byte
	}{
		{"32 bytes", "governance-malformed", valid[:32]},
		{"another module", "governance-wrong-module", otherModule(valid)},
		{"action 1", "governance-unsupported-action", gov(ActionRegisterChain, self, contract...)},
		{"the action before the length", "governance-unsupported-action", gov(ActionRegisterChain, self, contract[:31]...)},
		{"66 bytes", "governance-malformed", valid[:66]},
		{"68 bytes", "governance-malformed", append(append([]byte(nil), valid...), 0)},
		{"the length before the target", "governance-malformed", gov(ActionUpgradeContract, 0, contract[:31]...)},
		{"every chain", "governance-wrong-target-chain", gov(ActionUpgradeContract, 0, contract...)},
		{"another chain", "governance-wrong-target-chain", gov(ActionUpgradeContract, 2, contract...)},
	} {
		got, err := ParseUpgrade(c.p, self)
		if code(err) != c.want || got != ([32]byte{}) {
			t.Errorf("%s: %x, %q; want %q", c.name, got, code(err), c.want)
		}
	}
}

func TestParsePauserAddresses(t *testing.T) {
	role := func(b byte) []byte {
		r := make([]byte, 21)
		r[0], r[20] = 20, b
		return r
	}
	join := func(parts ...[]byte) []byte {
		var out []byte
		for _, p := range parts {
			out = append(out, p...)
		}
		return out
	}
	for _, c := range []struct {
		name  string
		body  []byte
		roles [3]byte // each role's last byte; 0 for unassigned
	}{
		{"three roles", join(role(1), role(2), role(3)), [3]byte{1, 2, 3}},
		{"none", []byte{0, 0, 0}, [3]byte{}},
		{"the freezer unassigned", join(role(1), []byte{0}, role(3)), [3]byte{1, 0, 3}},
	} {
		got, err := ParsePauserAddresses(gov(ActionSetPauserAddresses, self, c.body...), self)
		if err != nil || got.Pauser[19] != c.roles[0] || got.Freezer[19] != c.roles[1] || got.Unpauser[19] != c.roles[2] {
			t.Errorf("%s: %+v, %v", c.name, got, err)
		}
	}
	valid := gov(ActionSetPauserAddresses, self, join(role(1), role(2), role(3))...)
	short := append([]byte{19}, make([]byte, 19)...)
	for _, c := range []struct {
		name, want string
		p          []byte
	}{
		{"32 bytes", "governance-malformed", valid[:32]},
		{"another module", "governance-wrong-module", otherModule(valid)},
		{"action 1", "governance-unsupported-action", gov(ActionRegisterChain, self, join(role(1), role(2), role(3))...)},
		{"the action before the length", "governance-unsupported-action", gov(ActionRegisterChain, self)[:34]},
		{"34 bytes", "governance-malformed", valid[:34]},
		{"35 bytes, another chain", "governance-wrong-target-chain", gov(ActionSetPauserAddresses, 2)},
		{"no roles", "governance-malformed", valid[:35]},
		{"every chain", "governance-wrong-target-chain", gov(ActionSetPauserAddresses, 0, join(role(1), role(2), role(3))...)},
		{"another chain", "governance-wrong-target-chain", gov(ActionSetPauserAddresses, 2, join(role(1), role(2), role(3))...)},
		{"the target before the roles", "governance-wrong-target-chain", gov(ActionSetPauserAddresses, 2, 7)},
		{"a 19-byte role", "governance-malformed", gov(ActionSetPauserAddresses, self, join(short, role(2), role(3))...)},
		{"a 32-byte role", "governance-malformed", gov(ActionSetPauserAddresses, self, append([]byte{32}, make([]byte, 32)...)...)},
		{"a truncated role", "governance-malformed", valid[:len(valid)-1]},
		{"two roles", "governance-malformed", gov(ActionSetPauserAddresses, self, join(role(1), role(2))...)},
		{"a trailing byte", "governance-malformed", append(append([]byte(nil), valid...), 0)},
	} {
		got, err := ParsePauserAddresses(c.p, self)
		if code(err) != c.want || got != (PauserAddresses{}) {
			t.Errorf("%s: %+v, %q; want %q", c.name, got, code(err), c.want)
		}
	}
}
