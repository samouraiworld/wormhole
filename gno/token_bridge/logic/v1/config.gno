package logic

// The deployment configuration. This committed file fails closed: a negative
// limit makes init fail with invalid-configuration. The test runner replaces
// it with a test configuration, and a deployment with a reviewed
// configuration that meets every rule the README lists. A hand-written file
// meets only init's checks.
const (
	// GNOT's limits, in ugnot.
	gnotPerTransfer   int64 = -1
	gnotOutboundCap   int64 = -1
	gnotInboundBudget int64 = -1
)

// allowlistConfig returns the allowlist's entries, each a wrapped asset with
// its limits in wire units: open, redeemed, wrapped and sent out, or
// exit-only, only sent out.
func allowlistConfig() []assetConfig {
	return nil
}
