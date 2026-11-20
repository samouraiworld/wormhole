package logic

import (
	"strings"
	"testing"

	tb "gno.land/p/wormhole/tokenbridge/v0"
)

// Named tests for what the logic decides without another realm. Its entry
// points run in filetests, each on a fresh store, since the vault's state
// cannot be reset from here: filetests/ under the corpus's allowlist with
// limits that do not bind, and gno/testdata/logic-variant/limits/ under
// small limits.

// usdcHex is the token of the corpus's allowlist.
const usdcHex = "000000000000000000000000a000000000000000000000000000000000000048"

// TestConfig applies init's checks to configurations, each with one fault, on
// Wormhole chain 65535.
func TestConfig(t *testing.T) {
	good := assetConfig{2, usdcHex, 1, 2, 3, false}
	for _, c := range []struct {
		name                                    string
		perTransfer, outboundCap, inboundBudget int64
		assets                                  []assetConfig
		reason                                  string
	}{
		{"no wrapped asset", 1, 2, 3, nil, ""},
		{"a wrapped asset", 1, 2, 3, []assetConfig{good}, ""},
		{"zero limits", 0, 0, 0, []assetConfig{{2, usdcHex, 0, 0, 0, false}}, ""},
		{"the same token on two chains", 1, 2, 3, []assetConfig{good, {4, usdcHex, 1, 2, 3, false}}, ""},
		{"GNOT's per-transfer cap negative", -1, 2, 3, nil, "invalid-configuration"},
		{"GNOT's outbound cap negative", 1, -1, 3, nil, "invalid-configuration"},
		{"GNOT's inbound budget negative", 1, 2, -1, nil, "invalid-configuration"},
		{"an asset's per-transfer cap negative", 1, 2, 3, []assetConfig{{2, usdcHex, -1, 2, 3, false}}, "invalid-configuration"},
		{"an asset's outbound cap negative", 1, 2, 3, []assetConfig{{2, usdcHex, 1, -1, 3, false}}, "invalid-configuration"},
		{"an asset's inbound budget negative", 1, 2, 3, []assetConfig{{2, usdcHex, 1, 2, -1, false}}, "invalid-configuration"},
		{"an origin on chain 0", 1, 2, 3, []assetConfig{{0, usdcHex, 1, 2, 3, false}}, "invalid-configuration"},
		{"an origin on gno's chain", 1, 2, 3, []assetConfig{{65535, usdcHex, 1, 2, 3, false}}, "invalid-configuration"},
		{"an address that is not hex", 1, 2, 3, []assetConfig{{2, usdcHex[:63] + "z", 1, 2, 3, false}}, "invalid-configuration"},
		{"a short address", 1, 2, 3, []assetConfig{{2, usdcHex[:62], 1, 2, 3, false}}, "invalid-configuration"},
		{"an asset twice", 1, 2, 3, []assetConfig{good, good}, "invalid-configuration"},
		// The decoded origin is the key, not the text that names it.
		{"an asset twice, once in uppercase", 1, 2, 3, []assetConfig{good, {2, strings.ToUpper(usdcHex), 1, 2, 3, false}},
			"invalid-configuration"},
		{"an exit-only asset", 1, 2, 3, []assetConfig{{2, usdcHex, 1, 2, 3, true}}, ""},
		{"an asset both open and exit-only", 1, 2, 3, []assetConfig{good, {2, usdcHex, 1, 2, 3, true}},
			"invalid-configuration"},
		{"an exit-only asset with a negative cap", 1, 2, 3, []assetConfig{{2, usdcHex, 1, -1, 3, true}},
			"invalid-configuration"},
	} {
		if got := checkConfig(c.perTransfer, c.outboundCap, c.inboundBudget, c.assets, 65535); got != c.reason {
			t.Errorf("%s: %q, want %q", c.name, got, c.reason)
		}
	}
}

// TestWindow pins the limits' arithmetic on one window: what counts is the current
// hour and the 24 before it, and an amount fits up to the limit exactly.
func TestWindow(t *testing.T) {
	const h = 500_000
	w := &window{}
	if w.sum(h) != 0 || !w.fits(h, 150, 150) || w.fits(h, 151, 150) || !w.fits(h, 0, 0) {
		t.Fatal("an empty window")
	}
	w.count(h, 100)
	if w.sum(h) != 100 || !w.fits(h, 50, 150) || w.fits(h, 51, 150) {
		t.Errorf("after 100: sum %d", w.sum(h))
	}
	// The next hour adds its own bucket, and the same hour adds to its own.
	w.count(h+1, 50)
	w.count(h+1, 0)
	if w.sum(h+1) != 150 || !w.fits(h+1, 0, 150) || w.fits(h+1, 1, 150) {
		t.Errorf("an hour later: sum %d", w.sum(h+1))
	}
	// The 24th hour after h still counts h; the 25th does not.
	if w.sum(h+24) != 150 {
		t.Errorf("at h+24: sum %d", w.sum(h+24))
	}
	if w.sum(h+25) != 50 || !w.fits(h+25, 100, 150) || w.fits(h+25, 101, 150) {
		t.Errorf("at h+25: sum %d", w.sum(h+25))
	}
	if w.sum(h+26) != 0 {
		t.Errorf("at h+26: sum %d", w.sum(h+26))
	}
	// h+25 lands in h's bucket, which restarts instead of adding to h's count.
	w.count(h+25, 70)
	if w.sum(h+25) != 120 || w.sum(h+26) != 70 {
		t.Errorf("after h's bucket came round: %d, %d", w.sum(h+25), w.sum(h+26))
	}
	// Near hour 0, empty buckets, whose hour reads as 0, count nothing, and hour
	// 0's own count holds for its 25 hours.
	early := &window{}
	if early.sum(0) != 0 || early.sum(3) != 0 {
		t.Error("an empty window near hour 0")
	}
	early.count(0, 5)
	if early.sum(0) != 5 || early.sum(24) != 5 || early.sum(25) != 0 {
		t.Errorf("hour 0: %d, %d, %d", early.sum(0), early.sum(24), early.sum(25))
	}
}

// TestWindowAtTheInt64Bound pins the window rule where amount + sum would wrap:
// with MaxInt64 - 1 counted, under a limit of MaxInt64, one unit fits and two
// do not, whether the count sits in one bucket or in the first and last of the
// 25. Under a small limit, an amount near MaxInt64 never fits. Both of an
// asset's windows are the same type, so each is checked.
func TestWindowAtTheInt64Bound(t *testing.T) {
	const h = 500_000
	a := &asset{}
	for name, w := range map[string]*window{"outbound": &a.outbound, "inbound": &a.inbound} {
		w.count(h, maxInt64-1)
		if w.sum(h) != maxInt64-1 || !w.fits(h, 1, maxInt64) || w.fits(h, 2, maxInt64) ||
			w.fits(h, maxInt64, maxInt64) {
			t.Errorf("%s, one bucket: sum %d", name, w.sum(h))
		}
	}
	split := &window{}
	split.count(h, 1<<62)
	split.count(h+24, 1<<62-2)
	if split.sum(h+24) != maxInt64-1 || !split.fits(h+24, 1, maxInt64) || split.fits(h+24, 2, maxInt64) {
		t.Errorf("split across the window: sum %d", split.sum(h+24))
	}
	// Once the first bucket has left, its half fits again.
	if split.sum(h+25) != 1<<62-2 || !split.fits(h+25, 1<<62+1, maxInt64) || split.fits(h+25, 1<<62+2, maxInt64) {
		t.Errorf("after the first bucket left: sum %d", split.sum(h+25))
	}
	small := &window{}
	small.count(h, 900)
	if !small.fits(h, 100, 1000) || small.fits(h, 101, 1000) || small.fits(h, maxInt64, 1000) ||
		small.fits(h, maxInt64-899, 1000) {
		t.Errorf("a small limit: sum %d", small.sum(h))
	}
}

// TestDecimal pins the amounts Render writes.
func TestDecimal(t *testing.T) {
	for _, c := range []struct {
		amount int64
		d      int
		want   string
	}{
		{0, 0, "0"},
		{120, 0, "120"},
		{0, 6, "0.000000"},
		{1, 6, "0.000001"},
		{999_999, 6, "0.999999"},
		{1_000_000, 6, "1.000000"},
		{1_234_567_890, 6, "1234.567890"},
	} {
		if got := decimal(c.amount, c.d); got != c.want {
			t.Errorf("decimal(%d, %d) = %q, want %q", c.amount, c.d, got, c.want)
		}
	}
}

// TestRenderOrigin pins how Render names an asset on the allowlist: its chain
// in decimal from both of its bytes, then its address in hex, and its status.
func TestRenderOrigin(cur realm, t *testing.T) {
	usdc, _ := hex32(usdcHex)
	key := tb.Origin{Chain: 258, Address: usdc}.Key()
	allowlist.Set(key, &asset{perTransfer: 1, outboundCap: 2, inboundBudget: 3, exitOnly: true})
	page := Render("")
	allowlist.Remove(key)
	if !strings.Contains(page, "| 258:"+usdcHex+" | exit-only | 1 | 0 / 2 | 0 / 3 |\n") {
		t.Errorf("Render: %s", page)
	}
}

// TestAssetOf pins which origins have limits: GNOT's own, and what the
// allowlist holds. GNOT's address on another chain is neither.
func TestAssetOf(t *testing.T) {
	usdc, ok := hex32(usdcHex)
	if !ok {
		t.Fatal("usdcHex")
	}
	if assetOf(tb.Origin{Chain: 65535, Address: tb.GNOTAddress()}) != gnot {
		t.Error("GNOT's origin")
	}
	if assetOf(tb.Origin{Chain: 2, Address: tb.GNOTAddress()}) != nil {
		t.Error("GNOT's address on another chain")
	}
	if assetOf(tb.Origin{Chain: 65535, Address: usdc}) != nil {
		t.Error("another address on gno's chain")
	}
	if assetOf(tb.Origin{Chain: 2, Address: usdc}) == nil {
		t.Error("the allowlisted asset")
	}
	if assetOf(tb.Origin{Chain: 4, Address: usdc}) != nil {
		t.Error("the same address on another chain")
	}
}

// TestHex32 pins the decode the reads and init rely on.
func TestHex32(t *testing.T) {
	if _, ok := hex32(usdcHex); !ok {
		t.Error("64 hex characters")
	}
	// The last decodes to 32 bytes before the character that is not hex.
	for _, bad := range []string{"", "zz", usdcHex[:62], usdcHex + "00", usdcHex[:63] + "z", usdcHex + "zz"} {
		if _, ok := hex32(bad); ok {
			t.Errorf("%q decodes", bad)
		}
	}
}
