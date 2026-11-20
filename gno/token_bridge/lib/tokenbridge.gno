// Package tokenbridge holds the wire formats of gno's Wormhole token bridge:
// parsers and encoders for the transfer and AssetMeta payloads, parsers for the
// bridge's governance payloads, the amount helpers, GNOT's token address, the
// wrapped-token naming rules, and the values the logic realm passes to the
// vault.
//
// It is stateless and decides only what the bytes decide. Whether a VAA is
// authentic, its emitter a registered peer or its transfer already redeemed is
// for the realms to check: nothing here verifies a signature.
//
// Errors carry stable reason codes as their text: invalid-payload,
// amount-out-of-range, governance-malformed, governance-wrong-module,
// governance-unsupported-action, governance-wrong-target-chain,
// register-invalid-chain and register-zero-emitter.
package tokenbridge

import "crypto/keccak256"

// reason is an error whose text is a reason code.
type reason string

func (r reason) Error() string { return string(r) }

const (
	errInvalidPayload reason = "invalid-payload"
	errAmountRange    reason = "amount-out-of-range"
	errGovMalformed   reason = "governance-malformed"
	errGovModule      reason = "governance-wrong-module"
	errGovUnsupported reason = "governance-unsupported-action"
	errGovTarget      reason = "governance-wrong-target-chain"
	errRegisterChain  reason = "register-invalid-chain"
	errRegisterZero   reason = "register-zero-emitter"
)

const (
	// TransferLen is the length of payload 1, and of payload 3 before the
	// bytes it carries.
	TransferLen = 133
	// AssetMetaLen is the length of payload 2.
	AssetMetaLen = 100
	// MaxTransferPayload is the most payload 3 can carry for Core to publish
	// it: Core's 2048-byte cap less TransferLen.
	MaxTransferPayload = 2048 - TransferLen
)

// Origin names a token by its origin chain and its 32-byte address there.
type Origin struct {
	Chain   uint16
	Address [32]byte
}

// Key returns the origin key: the chain, big-endian, then the address, 34
// bytes.
func (o Origin) Key() string {
	b := make([]byte, 34)
	putUint16(b, o.Chain)
	copy(b[2:], o.Address[:])
	return string(b)
}

// ReplayKey returns a transfer's replay key: its emitter chain (2 bytes),
// emitter (32) and sequence (8), big-endian, 42 bytes.
func ReplayKey(emitterChain uint16, emitter [32]byte, sequence uint64) string {
	b := make([]byte, 42)
	putUint16(b, emitterChain)
	copy(b[2:34], emitter[:])
	for i := 0; i < 8; i++ {
		b[34+i] = byte(sequence >> (56 - 8*i))
	}
	return string(b)
}

// gnotAddress is GNOT's token address: 0x01 followed by the last 31 bytes of
// keccak256("ugnot"), as CosmWasm names its native denominations.
var gnotAddress = func() [32]byte {
	a := keccak256.Sum256([]byte("ugnot"))
	a[0] = 1
	return a
}()

// GNOTAddress returns GNOT's 32-byte token address.
func GNOTAddress() [32]byte { return gnotAddress }

// Int64 returns a big-endian uint256 as an int64. Above the int64 maximum it
// fails with amount-out-of-range.
func Int64(u [32]byte) (int64, error) {
	for _, c := range u[:24] {
		if c != 0 {
			return 0, errAmountRange
		}
	}
	if u[24] >= 0x80 {
		return 0, errAmountRange
	}
	var n int64
	for _, c := range u[24:] {
		n = n<<8 | int64(c)
	}
	return n, nil
}

// Uint256 returns n as a big-endian uint256. A negative n fails with
// amount-out-of-range, since the wire field is unsigned.
func Uint256(n int64) ([32]byte, error) {
	var u [32]byte
	if n < 0 {
		return u, errAmountRange
	}
	for i := 0; i < 8; i++ {
		u[31-i] = byte(n >> (8 * i))
	}
	return u, nil
}

// WrapperDecimals returns the decimals of the wrapper for an asset with d
// decimals: min(d, 8). Amounts on the wire keep at most 8 decimals, so a
// wrapper's amounts need no conversion.
func WrapperDecimals(d uint8) uint8 {
	if d > 8 {
		return 8
	}
	return d
}

// Transfer is a parsed payload 1 or 3. Amounts stay as on the wire,
// big-endian uint256: a caller converts them with Int64 where its own order
// of checks puts the range check.
type Transfer struct {
	PayloadID uint8 // 1 or 3
	Amount    [32]byte
	Token     Origin
	To        [32]byte
	ToChain   uint16
	Fee       [32]byte // payload 1 only
	From      [32]byte // payload 3 only
	Payload   []byte   // payload 3 only: a sub-slice of p with no spare capacity, never a new allocation
}

// ParseTransfer parses payload 1, exactly TransferLen bytes, or payload 3, at
// least TransferLen. Anything else fails with invalid-payload.
//
// Payload aliases p, so whoever can change p can change it: a caller copies
// what it keeps.
func ParseTransfer(p []byte) (Transfer, error) {
	if len(p) < TransferLen || (p[0] != 1 && p[0] != 3) || (p[0] == 1 && len(p) != TransferLen) {
		return Transfer{}, errInvalidPayload
	}
	t := Transfer{PayloadID: p[0], ToChain: uint16At(p[99:])}
	copy(t.Amount[:], p[1:33])
	copy(t.Token.Address[:], p[33:65])
	t.Token.Chain = uint16At(p[65:])
	copy(t.To[:], p[67:99])
	if t.PayloadID == 1 {
		copy(t.Fee[:], p[101:TransferLen])
	} else {
		copy(t.From[:], p[101:TransferLen])
		t.Payload = p[TransferLen:len(p):len(p)]
	}
	return t, nil
}

// EncodeTransfer returns payload 1. A negative amount or fee fails with
// amount-out-of-range.
func EncodeTransfer(amount int64, token Origin, to [32]byte, toChain uint16, fee int64) ([]byte, error) {
	f, err := Uint256(fee)
	if err != nil {
		return nil, err
	}
	return encodeTransfer(1, amount, token, to, toChain, f, nil)
}

// EncodeTransferWithPayload returns payload 3, naming the sender by its
// 32-byte address. A negative amount fails with amount-out-of-range.
func EncodeTransferWithPayload(amount int64, token Origin, to [32]byte, toChain uint16, from [32]byte,
	payload []byte,
) ([]byte, error) {
	return encodeTransfer(3, amount, token, to, toChain, from, payload)
}

// encodeTransfer writes a transfer's 133 bytes, whose last 32 are last, then
// tail.
func encodeTransfer(id uint8, amount int64, token Origin, to [32]byte, toChain uint16, last [32]byte,
	tail []byte,
) ([]byte, error) {
	a, err := Uint256(amount)
	if err != nil {
		return nil, err
	}
	b := make([]byte, TransferLen, TransferLen+len(tail))
	b[0] = id
	copy(b[1:33], a[:])
	copy(b[33:65], token.Address[:])
	putUint16(b[65:], token.Chain)
	copy(b[67:99], to[:])
	putUint16(b[99:], toChain)
	copy(b[101:TransferLen], last[:])
	return append(b, tail...), nil
}

// AssetMeta is a parsed payload 2: a token's metadata, which a peer attests
// so that other chains can wrap it.
type AssetMeta struct {
	Token    Origin
	Decimals uint8
	Symbol   [32]byte
	Name     [32]byte
}

// ParseAssetMeta parses payload 2, exactly AssetMetaLen bytes. Anything else
// fails with invalid-payload.
func ParseAssetMeta(p []byte) (AssetMeta, error) {
	if len(p) != AssetMetaLen || p[0] != 2 {
		return AssetMeta{}, errInvalidPayload
	}
	m := AssetMeta{Decimals: p[35]}
	copy(m.Token.Address[:], p[1:33])
	m.Token.Chain = uint16At(p[33:])
	copy(m.Symbol[:], p[36:68])
	copy(m.Name[:], p[68:AssetMetaLen])
	return m, nil
}

// EncodeAssetMeta returns payload 2.
func EncodeAssetMeta(m AssetMeta) []byte {
	b := make([]byte, AssetMetaLen)
	b[0] = 2
	copy(b[1:33], m.Token.Address[:])
	putUint16(b[33:], m.Token.Chain)
	b[35] = m.Decimals
	copy(b[36:68], m.Symbol[:])
	copy(b[68:AssetMetaLen], m.Name[:])
	return b
}

// Claim is what the logic realm records at the vault for a transfer it does not
// pay at once. The vault copies its fields, and adds the rest itself: whether
// the claim was delayed, and its state.
type Claim struct {
	Digest      [32]byte // keccak256(keccak256(body)) of the verified VAA
	PayloadID   uint8    // 1 or 3
	Recipient   address  // the payload's to[12:]
	Asset       Origin   // GNOT's origin, or a wrapped asset's
	Amount      int64
	Fee         int64 // payload 1's relayer fee; 0 for payload 3
	BodyLen     int
	ReleaseTime int64 // block time, in seconds
}

func putUint16(b []byte, v uint16) {
	b[0] = byte(v >> 8)
	b[1] = byte(v)
}

func uint16At(b []byte) uint16 { return uint16(b[0])<<8 | uint16(b[1]) }
