// Package tbsender is a test-only realm sender of the token bridge: it sends
// out the wrapped tokens it holds, through the logic it was written against,
// paying Core's message fee itself first, as the logic asks of a
// realm. It also tries what a realm may not do: send GNOT, which only a direct
// user call may.
package tbsender

import (
	"chain"
	"chain/banker"

	logic "gno.land/r/wormhole/tokenbridge/logic/v1"
)

// PayFee pays Core amount ugnot out of this realm's own balance.
func PayFee(cur realm, amount int64) {
	banker.NewBanker(banker.BankerTypeRealmSend, cur).SendCoins(cur.Address(),
		chain.PackageAddress("gno.land/r/wormhole/core"), chain.NewCoins(chain.NewCoin("ugnot", amount)))
}

// SendWrapped sends amount of this realm's wrapped token symbol out.
func SendWrapped(cur realm, symbol string, amount int64, recipientChain uint16, recipient [32]byte,
	fee int64,
) uint64 {
	return logic.TransferWrapped(cross(cur), symbol, amount, recipientChain, recipient, fee, 0)
}

// SendWrappedWithPayload sends amount of this realm's wrapped token symbol out
// with a payload, from this realm's address.
func SendWrappedWithPayload(cur realm, symbol string, amount int64, recipientChain uint16, recipient [32]byte,
	payload []byte,
) uint64 {
	return logic.TransferWrappedWithPayload(cross(cur), symbol, amount, recipientChain, recipient, payload, 0)
}

// SendGNOT tries to send GNOT as a realm.
func SendGNOT(cur realm, amount int64, recipientChain uint16, recipient [32]byte) uint64 {
	return logic.TransferGNOT(cross(cur), amount, recipientChain, recipient, 0, 0)
}

// Attest publishes GNOT's AssetMeta as a realm.
func Attest(cur realm) uint64 {
	return logic.AttestGNOT(cross(cur), 0)
}
