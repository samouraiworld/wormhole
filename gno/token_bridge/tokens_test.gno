package tokenbridge

import (
	"strings"
	"testing"
)

// TestWrappedTokenFunctions moves wrapped balances as the caller, on the
// token's ledger. An unknown symbol fails with wrapped-not-found; a refusal
// of the ledger panics with grc20's own error text.
func TestWrappedTokenFunctions(cur realm, t *testing.T) {
	reset()
	w := wrappedAsset0(cur, t)
	start := BalanceOf(w, testUser)
	testing.SetRealm(testing.NewUserRealm(testUser))
	for _, f := range []func(){
		func() { Transfer(cross(cur), "NOPE", testOther, 1) },
		func() { Approve(cross(cur), "NOPE", testOther, 1) },
		func() { TransferFrom(cross(cur), "NOPE", testUser, testOther, 1) },
	} {
		if got := abort(f); got != "wrapped-not-found" {
			t.Errorf("unknown symbol: %q", got)
		}
	}
	for _, c := range []struct {
		name, reason string
		fn           func()
	}{
		{"more than the balance", "insufficient balance", func() { Transfer(cross(cur), w, testOther, start+1) }},
		{"to oneself", "cannot send transfer to self", func() { Transfer(cross(cur), w, testUser, 1) }},
		{"a negative allowance", "invalid amount", func() { Approve(cross(cur), w, testOther, -1) }},
		{"without an allowance", "insufficient allowance", func() { TransferFrom(cross(cur), w, testUser, testOther, 1) }},
	} {
		if got := abort(c.fn); got != c.reason {
			t.Errorf("%s: %q", c.name, got)
		}
	}
	if got := abort(func() { Transfer(cross(cur), w, testOther, 10) }); got != "" {
		t.Fatalf("Transfer: %q", got)
	}
	if got := abort(func() { Approve(cross(cur), w, testOther, 4) }); got != "" {
		t.Fatalf("Approve: %q", got)
	}
	testing.SetRealm(testing.NewUserRealm(testOther))
	if got := abort(func() { TransferFrom(cross(cur), w, testUser, testOther, 3) }); got != "" {
		t.Fatalf("TransferFrom: %q", got)
	}
	if BalanceOf(w, testUser) != start-13 || BalanceOf(w, testOther) < 13 || Allowance(w, testUser, testOther) != 1 {
		t.Errorf("balances %d %d, allowance %d", BalanceOf(w, testUser), BalanceOf(w, testOther),
			Allowance(w, testUser, testOther))
	}
	if BalanceOf("NOPE", testUser) != 0 || Allowance("NOPE", testUser, testOther) != 0 || TotalSupply("NOPE") != 0 {
		t.Error("an unknown symbol reads non-zero")
	}
}

// TestRender shows the vault's state, never its path argument, with every
// pause and chain-ID state.
func TestRender(cur realm, t *testing.T) {
	reset()
	page := Render("](javascript:x)")
	for _, want := range []string{"# Wormhole token bridge", "bound to dev (no pending confirmation)", "Status: running",
		"pauser unassigned · freezer unassigned · unpauser unassigned", "Locked GNOT: 0.000000",
		"No peers registered"} {
		if !strings.Contains(page, want) {
			t.Errorf("missing %q in\n%s", want, page)
		}
	}
	if strings.Contains(page, "javascript") {
		t.Error("Render echoes its path")
	}
	registerPeers(cur, t)
	pauseRoles(cur, t)
	lockGNOT(cur, t, 1_234_567_890)
	setChainID("forked")
	pendingChainID, proposedAt = "forked", testTime
	paused, pauseExpiry = true, testTime+pauseDuration
	page = Render("")
	for _, want := range []string{"bound to dev (forked proposed at 2027-01-15T08:00:00Z)",
		"Status: paused until 2027-01-20T08:00:00Z, frozen (runtime chain ID differs)",
		"Locked GNOT: 1234.567890", "| 2 | a0a1a2", "| 3 | b0b1b2", "pauser " + string(pauserAddress())} {
		if !strings.Contains(page, want) {
			t.Errorf("missing %q in\n%s", want, page)
		}
	}
	pauseExpiry = maxInt64
	if page := Render(""); !strings.Contains(page, "Status: paused until the unpauser lifts it, frozen") {
		t.Errorf("a freeze renders as\n%s", page)
	}
	if decimal(5, 6) != "0.000005" || decimal(1_000_000, 6) != "1.000000" || decimal(7, 0) != "7" {
		t.Error("decimal")
	}
}

func pauserAddress() address { return pauser }
