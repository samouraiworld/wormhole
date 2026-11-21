package tokenbridge

import (
	"strings"
	"testing"
)

func string32(s string) [32]byte {
	var b [32]byte
	copy(b[:], s)
	return b
}

func TestString32(t *testing.T) {
	for _, c := range []struct{ in, want string }{
		{"USDC", "USDC"},
		{"", ""},
		{"AB\x00CD", "AB"},
		{strings.Repeat("x", 32), strings.Repeat("x", 32)},
	} {
		if got := String32(string32(c.in)); got != c.want {
			t.Errorf("String32(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestPad32(t *testing.T) {
	if b, ok := Pad32("GNOT"); !ok || hexOf(b[:]) != "474e4f54"+zeros(28) {
		t.Errorf("Pad32(GNOT) = %x, %v", b, ok)
	}
	if b, ok := Pad32(strings.Repeat("y", 32)); !ok || String32(b) != strings.Repeat("y", 32) {
		t.Errorf("Pad32 of 32 bytes = %x, %v", b, ok)
	}
	for _, s := range []string{"", strings.Repeat("y", 33), "GN\x00OT", "\x00"} {
		if b, ok := Pad32(s); ok || b != ([32]byte{}) {
			t.Errorf("Pad32 of %d bytes = %x, %v", len(s), b, ok)
		}
	}
}

// TestValidName pins grc20's name rule (p/nt/grc20/v0/token.gno, validName)
// at its edges.
func TestValidName(t *testing.T) {
	for _, c := range []struct {
		name string
		want bool
	}{
		{"", false},
		{"x", true},
		{strings.Repeat("x", 64), true},
		{strings.Repeat("x", 65), false},
		{strings.Repeat("é", 32), true}, // 64 bytes: grc20 counts bytes, not runes
		{strings.Repeat("é", 33), false},
		{"USD Coin", true},
		{"a\x1fb", false},
		{"a\x7fb", false},
		{"a\tb", false},
		{"a\x00b", false},
		{"Ünïcödé", true},
		{"\u0080", true},   // a C1 control character, which grc20 allows
		{"\xff\xfe", true}, // invalid UTF-8 ranges as U+FFFD, which grc20 allows
		{"]( | `", true},   // markdown, which only Render must neutralize
	} {
		if got := ValidName(c.name); got != c.want {
			t.Errorf("ValidName(%q) = %v", c.name, got)
		}
	}
}

// TestValidNameASCII checks every ASCII byte inside a name against grc20's
// rule: allowed unless below 0x20 or 0x7f.
func TestValidNameASCII(t *testing.T) {
	for c := 0; c < 0x80; c++ {
		name := "a" + string([]byte{byte(c)}) + "b"
		if got, want := ValidName(name), c >= 0x20 && c != 0x7f; got != want {
			t.Errorf("ValidName(%q) = %v, want %v", name, got, want)
		}
	}
}

// TestValidSymbolASCII checks every ASCII byte inside a symbol against
// grc20's alphabet, so that a range admitting a neighbor of A-Z, a-z or 0-9
// fails. A symbol grc20 refused would make the wrapper's creation fail for
// good.
func TestValidSymbolASCII(t *testing.T) {
	const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
	for c := 0; c < 0x80; c++ {
		symbol := "A" + string([]byte{byte(c)}) + "B"
		if got, want := ValidSymbol(symbol), strings.Contains(alphabet, string([]byte{byte(c)})); got != want {
			t.Errorf("ValidSymbol(%q) = %v, want %v", symbol, got, want)
		}
	}
}

// TestValidSymbol pins grc20's symbol rule (validSymbol) at its edges.
func TestValidSymbol(t *testing.T) {
	for _, c := range []struct {
		symbol string
		want   bool
	}{
		{"", false},
		{"USDC", true},
		{"a-b_c9", true},
		{strings.Repeat("A", 11), true},
		{strings.Repeat("A", 12), false},
		{"US.DC", false},
		{"U|SD", false},
		{"US DC", false},
		{"USD/C", false},
		{"É", false},
		{"\x00", false},
	} {
		if got := ValidSymbol(c.symbol); got != c.want {
			t.Errorf("ValidSymbol(%q) = %v", c.symbol, got)
		}
	}
}

func TestWrappedName(t *testing.T) {
	meta := func(name string, chain uint16) AssetMeta {
		m := AssetMeta{Name: string32(name), Token: Origin{Chain: chain}}
		for i := range m.Token.Address {
			m.Token.Address[i] = byte(i)
		}
		return m
	}
	tail := "0c0d0e0f101112131415161718191a1b1c1d1e1f" // the last 20 bytes of the address
	for _, c := range []struct {
		name  string
		chain uint16
		want  string
	}{
		{"USD Coin", 2, "USD Coin (Wormhole)"},
		{strings.Repeat("n", 32), 2, strings.Repeat("n", 32) + " (Wormhole)"},
		// The naming rules keep the suffix for an empty name too, since grc20
		// accepts the result.
		{"", 2, " (Wormhole)"},
		{"bad\x01name", 2, "Wormhole 2:" + tail},
		{"bad\x7f", 65535, "Wormhole 65535:" + tail},
	} {
		if got := WrappedName(meta(c.name, c.chain)); got != c.want {
			t.Errorf("WrappedName(%q) = %q, want %q", c.name, got, c.want)
		}
	}
	if got := WrappedName(meta("\x01", 65535)); len(got) != 55 || !ValidName(got) {
		t.Errorf("the longest fallback name is %d bytes: %q", len(got), got)
	}
}

func TestFallbackSymbol(t *testing.T) {
	for n, want := range map[int]string{1: "WH1", 12: "WH12", 999999999: "WH999999999"} {
		if got := FallbackSymbol(n); got != want || !ValidSymbol(got) {
			t.Errorf("FallbackSymbol(%d) = %q", n, got)
		}
	}
}
