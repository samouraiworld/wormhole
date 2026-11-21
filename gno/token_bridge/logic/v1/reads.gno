package logic

import (
	"encoding/hex"
	"strconv"
	"strings"

	tb "gno.land/p/wormhole/tokenbridge/v0"
)

// The read API. These are non-crossing, apply no gate, change nothing,
// and return only integers, booleans and strings. A read that cannot find what
// it names, or cannot decode its argument, returns zero values.

const (
	vaultPath    = "gno.land/r/wormhole/tokenbridge"
	gnotDecimals = 6
)

// Allowlisted reports whether the asset with this origin may be redeemed and
// wrapped: GNOT always, and a wrapped asset open on the allowlist.
func Allowlisted(tokenChain uint16, tokenAddressHex string) bool {
	a := assetAtHex(tokenChain, tokenAddressHex)
	return a != nil && !a.exitOnly
}

// ExitOnly reports whether the asset with this origin is on the allowlist as
// exit-only: it goes out under its outbound limits, and is neither redeemed nor
// wrapped.
func ExitOnly(tokenChain uint16, tokenAddressHex string) bool {
	a := assetAtHex(tokenChain, tokenAddressHex)
	return a != nil && a.exitOnly
}

// Limits returns whether this logic has limits for the asset with this origin,
// open or exit-only; its per-transfer cap; its outbound 24-hour cap and what
// the window counted; and its inbound 24-hour budget and what the window
// counted.
func Limits(tokenChain uint16, tokenAddressHex string) (found bool, perTransfer, outboundCap, outboundUsed,
	inboundBudget, inboundUsed int64,
) {
	a := assetAtHex(tokenChain, tokenAddressHex)
	if a == nil {
		return
	}
	hour := currentHour()
	return true, a.perTransfer, a.outboundCap, a.outbound.sum(hour), a.inboundBudget, a.inbound.sum(hour)
}

func assetAtHex(tokenChain uint16, tokenAddressHex string) *asset {
	token, ok := hex32(tokenAddressHex)
	if !ok {
		return nil
	}
	return assetOf(tb.Origin{Chain: tokenChain, Address: token})
}

// Render shows the limits of GNOT and of every asset on the allowlist, open or
// exit-only, and what their windows counted. It never echoes path. Origin keys
// are hex, so it writes nothing a peer chose.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Token bridge logic v1\n\n")
	b.WriteString("Vault: " + vaultPath + "\n\n")
	b.WriteString("GNOT in GNOT, other assets in wire units.\n\n")
	b.WriteString("| Asset | Status | Outbound per transfer | Outbound 24 h (used / cap) | Inbound 24 h (used / budget) |\n")
	b.WriteString("|---|---|---|---|---|\n")
	hour := currentHour()
	writeRow(&b, "GNOT", gnot, hour, gnotDecimals)
	allowlist.Iterate("", "", func(key string, value any) bool {
		label := strconv.Itoa(int(key[0])<<8|int(key[1])) + ":" + hex.EncodeToString([]byte(key[2:]))
		writeRow(&b, label, value.(*asset), hour, 0)
		return false
	})
	return b.String()
}

func writeRow(b *strings.Builder, label string, a *asset, hour int64, d int) {
	status := "open"
	if a.exitOnly {
		status = "exit-only"
	}
	b.WriteString("| " + label + " | " + status + " | " + decimal(a.perTransfer, d) + " | " +
		decimal(a.outbound.sum(hour), d) + " / " + decimal(a.outboundCap, d) + " | " +
		decimal(a.inbound.sum(hour), d) + " / " + decimal(a.inboundBudget, d) + " |\n")
}

// decimal writes a non-negative amount with d decimals.
func decimal(amount int64, d int) string {
	s := strconv.FormatInt(amount, 10)
	if d == 0 {
		return s
	}
	if len(s) <= d {
		s = strings.Repeat("0", d-len(s)+1) + s
	}
	return s[:len(s)-d] + "." + s[len(s)-d:]
}
