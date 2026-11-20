package tokenbridge

import (
	"crypto/keccak256"
	"encoding/hex"
	"strings"
	"testing"
)

func code(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func unhex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("bad hex: %v", err)
	}
	return b
}

// word returns the 32 bytes of a hex string of at most 64 characters,
// left-padded with zeros.
func word(t *testing.T, s string) [32]byte {
	t.Helper()
	var w [32]byte
	b := unhex(t, s)
	copy(w[32-len(b):], b)
	return w
}

func zeros(n int) string { return strings.Repeat("00", n) }

func hexOf(b []byte) string { return hex.EncodeToString(b) }

func TestKeys(t *testing.T) {
	emitter := word(t, "aa"+zeros(30)+"bb")
	got := hexOf([]byte(ReplayKey(0x0102, emitter, 0x0304050607080910)))
	if want := "0102" + "aa" + zeros(30) + "bb" + "0304050607080910"; got != want {
		t.Errorf("ReplayKey = %s, want %s", got, want)
	}
	if got := hexOf([]byte(Origin{Chain: 2, Address: emitter}.Key())); got != "0002aa"+zeros(30)+"bb" {
		t.Errorf("Origin.Key = %s", got)
	}
}

func TestGNOTAddress(t *testing.T) {
	h := keccak256.Sum256([]byte("ugnot"))
	a := GNOTAddress()
	if a[0] != 1 || string(a[1:]) != string(h[1:]) {
		t.Errorf("GNOTAddress = %x, want 01 then the last 31 bytes of keccak256(ugnot)", a)
	}
	if hexOf(a[:]) != testGNOTAddress {
		t.Errorf("GNOTAddress = %x, corpus %s", a, testGNOTAddress)
	}
	a[0] = 9
	if b := GNOTAddress(); b[0] != 1 {
		t.Error("GNOTAddress returned shared state")
	}
}

func TestAmounts(t *testing.T) {
	for _, c := range []struct {
		word string
		n    int64
		err  string
	}{
		{"00", 0, ""},
		{"01", 1, ""},
		{"7fffffffffffffff", 9223372036854775807, ""},
		{"8000000000000000", 0, "amount-out-of-range"},
		{"010000000000000000", 0, "amount-out-of-range"},
		{"01" + zeros(31), 0, "amount-out-of-range"},
		{strings.Repeat("ff", 32), 0, "amount-out-of-range"},
	} {
		n, err := Int64(word(t, c.word))
		if code(err) != c.err || n != c.n {
			t.Errorf("Int64(%s) = %d, %q; want %d, %q", c.word, n, code(err), c.n, c.err)
		}
	}
	for _, n := range []int64{0, 1, 0x0102, 9223372036854775807} {
		u, err := Uint256(n)
		if err != nil {
			t.Fatalf("Uint256(%d): %v", n, err)
		}
		if back, err := Int64(u); err != nil || back != n {
			t.Errorf("Int64(Uint256(%d)) = %d, %v", n, back, err)
		}
	}
	if u, _ := Uint256(0x0102); hexOf(u[:]) != zeros(30)+"0102" {
		t.Errorf("Uint256(0x0102) = %x", u)
	}
	if _, err := Uint256(-1); code(err) != "amount-out-of-range" {
		t.Errorf("Uint256(-1): %q", code(err))
	}
}

func TestWrapperDecimals(t *testing.T) {
	for d := 0; d <= 255; d++ {
		want := uint8(d)
		if d > 8 {
			want = 8
		}
		if got := WrapperDecimals(uint8(d)); got != want {
			t.Errorf("WrapperDecimals(%d) = %d", d, got)
		}
	}
}

// sampleTransfer is a payload 1 written out field by field.
const sampleTransfer = "01" + // payload ID
	"00000000000000000000000000000000000000000000000000000000000003e8" + // amount 1000
	"000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48" + // token address
	"0002" + // token chain
	"0000000000000000000000001111111111111111111111111111111111111111" + // to
	"ffff" + // to chain
	"000000000000000000000000000000000000000000000000000000000000000a" // fee 10

func TestParseTransfer(t *testing.T) {
	p := unhex(t, sampleTransfer)
	tr, err := ParseTransfer(p)
	if err != nil {
		t.Fatalf("ParseTransfer: %v", err)
	}
	amount, _ := Int64(tr.Amount)
	fee, _ := Int64(tr.Fee)
	if tr.PayloadID != 1 || amount != 1000 || tr.Token.Chain != 2 || tr.ToChain != 65535 || fee != 10 ||
		hexOf(tr.Token.Address[:]) != sampleTransfer[66:130] || hexOf(tr.To[:]) != sampleTransfer[134:198] ||
		tr.From != ([32]byte{}) || tr.Payload != nil {
		t.Errorf("ParseTransfer = %+v", tr)
	}
	for _, c := range []struct {
		name string
		p    []byte
	}{
		{"empty", nil},
		{"one byte short", p[:132]},
		{"one byte long", append(append([]byte(nil), p...), 0)},
		{"type 0", append([]byte{0}, p[1:]...)},
		{"type 2", append([]byte{2}, p[1:]...)},
		{"type 4", append([]byte{4}, p[1:]...)},
		{"type 3 short", append([]byte{3}, p[1:132]...)},
	} {
		if _, err := ParseTransfer(c.p); code(err) != "invalid-payload" {
			t.Errorf("%s: %q, want invalid-payload", c.name, code(err))
		}
	}
}

func TestParseTransferWithPayload(t *testing.T) {
	p3 := append([]byte{3}, unhex(t, sampleTransfer)[1:]...)
	tr, err := ParseTransfer(p3)
	if err != nil {
		t.Fatalf("ParseTransfer: %v", err)
	}
	if tr.PayloadID != 3 || hexOf(tr.From[:]) != sampleTransfer[202:] || tr.Fee != ([32]byte{}) ||
		len(tr.Payload) != 0 {
		t.Errorf("an empty payload 3 = %+v", tr)
	}
	// An input with spare capacity: Payload must not reach past the input's
	// length, so that appending to it cannot write over what follows.
	in := make([]byte, len(p3)+2, len(p3)+10)
	copy(in, p3)
	in[TransferLen], in[TransferLen+1] = 0xca, 0xfe
	p3 = in
	tr, err = ParseTransfer(p3)
	if err != nil || hexOf(tr.Payload) != "cafe" || cap(tr.Payload) != 2 {
		t.Fatalf("payload 3 with two bytes: %v, %x, cap %d", err, tr.Payload, cap(tr.Payload))
	}
	// Payload aliases its input, as documented.
	p3[TransferLen] = 0
	if tr.Payload[0] != 0 {
		t.Error("Payload does not alias the input")
	}
}

func TestEncodeTransfer(t *testing.T) {
	token := Origin{Chain: 2, Address: word(t, sampleTransfer[66:130])}
	to := word(t, sampleTransfer[134:198])
	p, err := EncodeTransfer(1000, token, to, 65535, 10)
	if err != nil || hexOf(p) != sampleTransfer || cap(p) != TransferLen {
		t.Errorf("EncodeTransfer = %x, %v, cap %d", p, err, cap(p))
	}
	if p, err := EncodeTransfer(0, token, to, 65535, 0); err != nil || len(p) != TransferLen {
		t.Errorf("a zero transfer: %v", err)
	}
	if _, err := EncodeTransfer(-1, token, to, 65535, 0); code(err) != "amount-out-of-range" {
		t.Errorf("a negative amount: %q", code(err))
	}
	if _, err := EncodeTransfer(1, token, to, 65535, -1); code(err) != "amount-out-of-range" {
		t.Errorf("a negative fee: %q", code(err))
	}
	from := word(t, sampleTransfer[202:])
	p3, err := EncodeTransferWithPayload(1000, token, to, 65535, from, []byte{0xca, 0xfe})
	if want := "03" + sampleTransfer[2:] + "cafe"; err != nil || hexOf(p3) != want || cap(p3) != len(p3) {
		t.Errorf("EncodeTransferWithPayload = %x, %v", p3, err)
	}
	if _, err := EncodeTransferWithPayload(-1, token, to, 65535, from, nil); code(err) != "amount-out-of-range" {
		t.Errorf("a negative payload-3 amount: %q", code(err))
	}
	if MaxTransferPayload != 1915 {
		t.Errorf("MaxTransferPayload = %d", MaxTransferPayload)
	}
}

// sampleMeta is a payload 2 written out field by field.
const sampleMeta = "02" + // payload ID
	"000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48" + // token address
	"0002" + // token chain
	"12" + // decimals 18
	"5553444300000000000000000000000000000000000000000000000000000000" + // symbol USDC
	"55534420436f696e000000000000000000000000000000000000000000000000" // name USD Coin

func TestAssetMeta(t *testing.T) {
	p := unhex(t, sampleMeta)
	m, err := ParseAssetMeta(p)
	if err != nil {
		t.Fatalf("ParseAssetMeta: %v", err)
	}
	if m.Token.Chain != 2 || m.Decimals != 18 || String32(m.Symbol) != "USDC" || String32(m.Name) != "USD Coin" ||
		hexOf(m.Token.Address[:]) != sampleMeta[2:66] {
		t.Errorf("ParseAssetMeta = %+v", m)
	}
	if got := hexOf(EncodeAssetMeta(m)); got != sampleMeta {
		t.Errorf("EncodeAssetMeta = %s", got)
	}
	for _, c := range []struct {
		name string
		p    []byte
	}{
		{"empty", nil},
		{"one byte short", p[:99]},
		{"one byte long", append(append([]byte(nil), p...), 0)},
		{"type 1", append([]byte{1}, p[1:]...)},
		{"type 3", append([]byte{3}, p[1:]...)},
	} {
		if _, err := ParseAssetMeta(c.p); code(err) != "invalid-payload" {
			t.Errorf("%s: %q, want invalid-payload", c.name, code(err))
		}
	}
}

// TestGeneratedPayloads runs the parser each generated payload's corpus step
// reaches, and requires the corpus's outcome and, when it accepts, the
// fields the Go side decoded.
func TestGeneratedPayloads(t *testing.T) {
	kinds := map[string]int{}
	for _, v := range testPayloads {
		kinds[v.kind]++
		p := unhex(t, v.payload)
		var err error
		var got, want string
		switch v.kind {
		case "transfer":
			var tr Transfer
			tr, err = ParseTransfer(p)
			got = hexOf([]byte{tr.PayloadID}) + hexOf(tr.Amount[:]) + hexOf(tr.Token.Address[:]) +
				hexOf([]byte{byte(tr.Token.Chain >> 8), byte(tr.Token.Chain)}) + hexOf(tr.To[:]) +
				hexOf([]byte{byte(tr.ToChain >> 8), byte(tr.ToChain)}) + hexOf(tr.Fee[:]) + hexOf(tr.From[:]) +
				hexOf(tr.Payload)
			want = hexOf([]byte{v.id}) + v.amount + v.token + chainHex(v.tokenChain) + v.to + chainHex(v.toChain) +
				v.fee + v.from + v.tail
			_, amountErr := Int64(tr.Amount)
			_, feeErr := Int64(tr.Fee)
			if err == nil && (code(amountErr) != v.amountReason || code(feeErr) != v.feeReason) {
				t.Errorf("%s: Int64 of the amount and fee: %q, %q; want %q, %q", v.name, code(amountErr),
					code(feeErr), v.amountReason, v.feeReason)
			}
		case "assetmeta":
			var m AssetMeta
			m, err = ParseAssetMeta(p)
			got = hexOf(m.Token.Address[:]) + chainHex(m.Token.Chain) + hexOf([]byte{m.Decimals}) +
				hexOf(m.Symbol[:]) + hexOf(m.Name[:])
			want = v.token + chainHex(v.tokenChain) + hexOf([]byte{v.decimals}) + v.symbol + v.metaName
		case "register":
			var chain uint16
			var emitter [32]byte
			chain, emitter, err = ParseRegisterChain(p, testChainID)
			got, want = chainHex(chain)+hexOf(emitter[:]), chainHex(v.chain)+v.emitter
		case "upgrade":
			var contract [32]byte
			contract, err = ParseUpgrade(p, testChainID)
			got, want = hexOf(contract[:]), v.contract
		case "pauser":
			var roles PauserAddresses
			roles, err = ParsePauserAddresses(p, testChainID)
			got = hexOf(roles.Pauser[:]) + hexOf(roles.Freezer[:]) + hexOf(roles.Unpauser[:])
			want = v.pauser + v.freezer + v.unpauser
		default:
			t.Fatalf("%s: unknown kind %q", v.name, v.kind)
		}
		if code(err) != v.reason {
			t.Errorf("%s: %q, want %q", v.name, code(err), v.reason)
			continue
		}
		if err == nil && got != want {
			t.Errorf("%s: fields\n%s, want\n%s", v.name, got, want)
		}
	}
	for _, kind := range []string{"transfer", "assetmeta", "register", "upgrade", "pauser"} {
		if kinds[kind] == 0 {
			t.Errorf("no generated payload of kind %s", kind)
		}
	}
}

func chainHex(c uint16) string { return hexOf([]byte{byte(c >> 8), byte(c)}) }
