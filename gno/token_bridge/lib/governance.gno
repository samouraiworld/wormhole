package tokenbridge

// module is the token bridge's governance module: "TokenBridge", left-padded
// with zeros to 32 bytes, as module is in
// ethereum/contracts/bridge/BridgeGovernance.sol.
const module = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" +
	"TokenBridge"

// The governance actions the bridge's entry points take.
// Action 3, chain-ID recovery, has none.
const (
	ActionRegisterChain      = 1
	ActionUpgradeContract    = 2
	ActionSetPauserAddresses = 4
)

// The parsers below check a governance VAA's payload once the vault has
// verified the VAA, checked its set and emitter and found it unconsumed.
// Each applies the payload checks in the reference model's order:
// the length, the module and the action byte, then its action's length
// before its target.

// governanceHeader checks that p has at least 33 bytes, names the
// TokenBridge module, and carries action.
func governanceHeader(p []byte, action uint8) error {
	if len(p) < 33 {
		return errGovMalformed
	}
	if string(p[:32]) != module {
		return errGovModule
	}
	if p[32] != action {
		return errGovUnsupported
	}
	return nil
}

// ParseRegisterChain checks a RegisterChain payload, exactly 69 bytes, for
// the bridge on Wormhole chain self, and returns the peer it registers: its
// chain and emitter. The target must be self or 0 (every chain), the peer's
// chain neither 0 nor self, and its emitter not all zeros. Whether the chain
// already has a peer is the vault's check.
func ParseRegisterChain(p []byte, self uint16) (uint16, [32]byte, error) {
	var emitter [32]byte
	if err := governanceHeader(p, ActionRegisterChain); err != nil {
		return 0, emitter, err
	}
	if len(p) != 69 {
		return 0, emitter, errGovMalformed
	}
	if target := uint16At(p[33:]); target != 0 && target != self {
		return 0, emitter, errGovTarget
	}
	chain := uint16At(p[35:])
	if chain == 0 || chain == self {
		return 0, emitter, errRegisterChain
	}
	copy(emitter[:], p[37:69])
	if emitter == ([32]byte{}) {
		return 0, emitter, errRegisterZero
	}
	return chain, emitter, nil
}

// ParseUpgrade checks an UpgradeContract payload, exactly 67 bytes, targeting
// chain self only, and returns its contract field: the new logic realm's
// address, left-padded to 32 bytes.
func ParseUpgrade(p []byte, self uint16) ([32]byte, error) {
	var contract [32]byte
	if err := governanceHeader(p, ActionUpgradeContract); err != nil {
		return contract, err
	}
	if len(p) != 67 {
		return contract, errGovMalformed
	}
	if uint16At(p[33:]) != self {
		return contract, errGovTarget
	}
	copy(contract[:], p[35:67])
	return contract, nil
}

// PauserAddresses are the three roles of whitepaper 0003 that a
// SetPauserAddresses payload assigns. An all-zero address leaves its role
// unassigned.
type PauserAddresses struct {
	Pauser, Freezer, Unpauser [20]byte
}

// ParsePauserAddresses checks a SetPauserAddresses payload targeting chain
// self only: 35 bytes, then each role as a length byte, 0 or 20, followed by
// that many bytes, with nothing after the third. The target is checked before
// the roles.
func ParsePauserAddresses(p []byte, self uint16) (PauserAddresses, error) {
	if err := governanceHeader(p, ActionSetPauserAddresses); err != nil {
		return PauserAddresses{}, err
	}
	if len(p) < 35 {
		return PauserAddresses{}, errGovMalformed
	}
	if uint16At(p[33:]) != self {
		return PauserAddresses{}, errGovTarget
	}
	var roles [3][20]byte
	i := 35
	for r := range roles {
		if i >= len(p) {
			return PauserAddresses{}, errGovMalformed
		}
		n := int(p[i])
		i++
		if (n != 0 && n != 20) || i+n > len(p) {
			return PauserAddresses{}, errGovMalformed
		}
		copy(roles[r][:], p[i:i+n])
		i += n
	}
	if i != len(p) {
		return PauserAddresses{}, errGovMalformed
	}
	return PauserAddresses{roles[0], roles[1], roles[2]}, nil
}
