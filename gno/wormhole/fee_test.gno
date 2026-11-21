package core

import (
	"chain"
	"chain/runtime"
	"strings"
	"testing"
)

// Named tests for the message fee: the publication's fee step,
// SetMessageFee and TransferFees (actions 3 and 4), and their edge
// cases. A test that calls transferFees directly runs as Core and
// never calls testing.SetRealm, which would change cur, the realm it pays
// from.

// coreAddress is Core's address, where a publisher pays the fee.
var coreAddress = chain.PackageAddress("gno.land/r/wormhole/core")

// feeRecipient is the corpus's payout recipient, the 20-byte address 0x…42.
const feeRecipient address = "g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqzzdfrzrc"

// pay sends Core n of denom, as a publisher does earlier in its transaction.
func pay(n int64, denom string) {
	testing.IssueCoins(coreAddress, chain.Coins{{denom, n}})
}

// word is n as a 32-byte big-endian integer.
func word(n uint64) []byte {
	w := make([]byte, 32)
	for i := 31; i >= 24; i-- {
		w[i] = byte(n)
		n >>= 8
	}
	return w
}

// feePayload is a SetMessageFee payload after its action byte.
func feePayload(target uint16, fee []byte) []byte {
	return append([]byte{byte(target >> 8), byte(target)}, fee...)
}

// payoutPayload is a TransferFees payload after its action byte, paying
// amount to the 32-byte recipient field to.
func payoutPayload(target uint16, amount, to []byte) []byte {
	p := append([]byte{byte(target >> 8), byte(target)}, amount...)
	return append(p, to...)
}

// field is addr's 20 bytes, left-padded to a 32-byte recipient field.
func field(t *testing.T, addr address) []byte {
	t.Helper()
	e := decoded(t, addr)
	return e[:]
}

// refusalBaseline sets a fee and a record unlike what reset leaves, so that a
// refusal that wrote either before its last check shows: the fee becomes 7
// and the record one below Core's ugnot balance. It returns the record.
func refusalBaseline() int64 {
	messageFee = 7
	recordedBalance = balance(coreAddress) - 1
	return recordedBalance
}

// asCore fails the test unless rlm, a test's cur, is Core's realm, which
// transferFees pays from.
func asCore(t *testing.T, rlm realm) {
	t.Helper()
	if rlm.Address() != coreAddress {
		t.Fatalf("the test runs as %s, not Core", rlm.Address())
	}
}

// TestSetMessageFee submits the corpus's SetMessageFee: the fee becomes 1
// ugnot and the digest is consumed, so a replay is refused. The fee then
// takes any value that fits an int64, 0 and the maximum included.
func TestSetMessageFee(cur realm, t *testing.T) {
	reset()
	setTime(testTime)
	raw := unhex(t, testSetMessageFee)
	if got := abort(func() { SubmitGovernance(cross(cur), raw) }); got != "" {
		t.Fatalf("%q", got)
	}
	if MessageFee() != 1 || consumed.Size() != 1 {
		t.Errorf("fee %d, %d digests consumed", MessageFee(), consumed.Size())
	}
	if got := abort(func() { SubmitGovernance(cross(cur), raw) }); got != "governance-replay" {
		t.Errorf("replayed: %q", got)
	}
	for i, fee := range []uint64{1<<63 - 1, 0} {
		if got := abort(func() {
			setMessageFee([32]byte{byte(i + 1)}, feePayload(wormholeChainID, word(fee)), wormholeChainID, coreAddress)
		}); got != "" || MessageFee() != int64(fee) {
			t.Errorf("fee %d: %q, now %d", fee, got, MessageFee())
		}
	}
}

// TestSetMessageFeeRecordsCore submits the corpus's SetMessageFee from
// another realm, which holds coins of its own: the balance recorded is
// Core's, never the submitter's.
func TestSetMessageFeeRecordsCore(cur realm, t *testing.T) {
	reset()
	setTime(testTime)
	submitter := chain.PackageAddress("gno.land/r/wormhole_test/governor")
	testing.IssueCoins(submitter, chain.Coins{{"ugnot", 1_000_003}})
	pay(3, "ugnot")
	if balance(submitter) == balance(coreAddress) {
		t.Fatal("the submitter and Core hold the same balance")
	}
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/governor"))
	if got := abort(func() { SubmitGovernance(cross(cur), unhex(t, testSetMessageFee)) }); got != "" {
		t.Fatalf("%q", got)
	}
	if recordedBalance != balance(coreAddress) {
		t.Errorf("record %d, Core holds %d", recordedBalance, balance(coreAddress))
	}
}

// TestFeeOutOfRange: a fee or an amount that does not fit an int64 is
// refused with governance-fee-out-of-range, whichever of its 25 high bytes
// is set and with all 256 bits set, and nothing changes: the fee, the
// consumed digests, Core's balance or the record.
func TestFeeOutOfRange(cur realm, t *testing.T) {
	reset()
	asCore(t, cur)
	pay(5, "ugnot")
	held := balance(coreAddress)
	recorded := refusalBaseline()
	var words [][]byte
	for i := 0; i <= 24; i++ {
		w := word(0)
		w[i] = 1
		if i == 24 {
			w[i] = 0x80 // 2^63
		}
		words = append(words, w)
	}
	all := make([]byte, 32)
	for i := range all {
		all[i] = 0xff
	}
	words = append(words, all)
	for i, w := range words {
		if got := abort(func() {
			setMessageFee([32]byte{1}, feePayload(wormholeChainID, w), wormholeChainID, coreAddress)
		}); got != "governance-fee-out-of-range" {
			t.Errorf("fee %d: %q", i, got)
		}
		if got := abort(func() {
			transferFees(cur, [32]byte{2}, payoutPayload(wormholeChainID, w, field(t, feeRecipient)), wormholeChainID)
		}); got != "governance-fee-out-of-range" {
			t.Errorf("amount %d: %q", i, got)
		}
	}
	if messageFee != 7 || consumed.Size() != 0 || balance(coreAddress) != held || recordedBalance != recorded {
		t.Error("a refusal changed state")
	}
}

// TestFeeRecipient: a recipient with any of its first 12 bytes set is refused
// with governance-fee-recipient, where EVM would truncate it, and nothing is
// paid or consumed.
func TestFeeRecipient(cur realm, t *testing.T) {
	reset()
	asCore(t, cur)
	pay(1, "ugnot")
	held := balance(coreAddress)
	recorded := refusalBaseline()
	before := balance(feeRecipient)
	for i := 0; i < 12; i++ {
		to := field(t, feeRecipient)
		to[i] = 1
		if got := abort(func() {
			transferFees(cur, [32]byte{1}, payoutPayload(wormholeChainID, word(1), to), wormholeChainID)
		}); got != "governance-fee-recipient" {
			t.Errorf("byte %d: %q", i, got)
		}
	}
	if messageFee != 7 || consumed.Size() != 0 || balance(coreAddress) != held || recordedBalance != recorded ||
		balance(feeRecipient) != before {
		t.Error("a refusal changed state")
	}
}

// TestPayoutExceedsBalance: a payout one above Core's ugnot balance is
// refused with governance-payout-exceeds-balance and changes nothing, its
// digest included. One equal to the balance empties Core, pays the
// recipient and records the balance it leaves.
func TestPayoutExceedsBalance(cur realm, t *testing.T) {
	reset()
	asCore(t, cur)
	pay(5, "ugnot")
	held := balance(coreAddress)
	recorded := refusalBaseline()
	before := balance(feeRecipient)
	to := field(t, feeRecipient)
	if got := abort(func() {
		transferFees(cur, [32]byte{1}, payoutPayload(0, word(uint64(held)+1), to), wormholeChainID)
	}); got != "governance-payout-exceeds-balance" {
		t.Fatalf("one above the balance: %q", got)
	}
	if messageFee != 7 || consumed.Size() != 0 || balance(coreAddress) != held || recordedBalance != recorded ||
		balance(feeRecipient) != before {
		t.Error("the refusal changed state")
	}
	if got := abort(func() {
		transferFees(cur, [32]byte{1}, payoutPayload(0, word(uint64(held)), to), wormholeChainID)
	}); got != "" {
		t.Fatalf("the whole balance: %q", got)
	}
	if !GovernanceConsumed([32]byte{1}) || balance(coreAddress) != 0 || recordedBalance != 0 ||
		balance(feeRecipient) != before+held {
		t.Error("the payout of the whole balance")
	}
}

// TestTransferFees submits the corpus's TransferFees VAAs. Paying 1 ugnot to
// 0x…42 is refused while Core holds none, without consuming the digest, and
// accepted once it holds 1. Paying nothing is accepted from an empty balance
// and sends nothing (gno's test banker would refuse a zero send from it).
func TestTransferFees(cur realm, t *testing.T) {
	reset()
	asCore(t, cur)
	setTime(testTime)
	if held := balance(coreAddress); held > 0 {
		sink := chain.PackageAddress("gno.land/r/wormhole_test/sink")
		transferFees(cur, [32]byte{0xdd}, payoutPayload(0, word(uint64(held)), field(t, sink)), wormholeChainID)
		reset()
	}
	one := unhex(t, testTransferFeesOne)
	if got := abort(func() { SubmitGovernance(cross(cur), one) }); got != "governance-payout-exceeds-balance" {
		t.Errorf("from an empty balance: %q", got)
	}
	if consumed.Size() != 0 {
		t.Error("the refused payout consumed its digest")
	}
	pay(1, "ugnot")
	before := balance(feeRecipient)
	if got := abort(func() { SubmitGovernance(cross(cur), one) }); got != "" {
		t.Fatalf("with 1 ugnot: %q", got)
	}
	if balance(feeRecipient) != before+1 || balance(coreAddress) != 0 || recordedBalance != 0 || consumed.Size() != 1 {
		t.Error("the payout of 1 ugnot")
	}
	if got := abort(func() { SubmitGovernance(cross(cur), unhex(t, testTransferFeesZero)) }); got != "" {
		t.Errorf("nothing, from an empty balance: %q", got)
	}
	if balance(feeRecipient) != before+1 || consumed.Size() != 2 {
		t.Error("the payout of nothing")
	}
}

// TestPayoutToCore pays Core's own address. Its balance does not change, so
// the record, read again after the send, still equals it: the payout leaves
// no credit that would let a publication go unpaid.
func TestPayoutToCore(cur realm, t *testing.T) {
	reset()
	asCore(t, cur)
	pay(10, "ugnot")
	held := balance(coreAddress)
	recordedBalance = held
	if got := abort(func() {
		transferFees(cur, [32]byte{1}, payoutPayload(0, word(4), field(t, coreAddress)), wormholeChainID)
	}); got != "" {
		t.Fatalf("%q", got)
	}
	if balance(coreAddress) != held || recordedBalance != held {
		t.Errorf("balance %d, record %d, want both %d", balance(coreAddress), recordedBalance, held)
	}
	messageFee = 1
	if got := abort(func() { PublishMessage(cross(cur), 0, nil, 1) }); got != "fee-unpaid" {
		t.Errorf("unpaid after the payout: %q", got)
	}
}

// TestPublishAfterPayout: a payout records the balance it leaves, so the
// publication after it is judged from there: unpaid, it is refused, and
// paid, it is accepted.
func TestPublishAfterPayout(cur realm, t *testing.T) {
	reset()
	asCore(t, cur)
	publish := func() string { return abort(func() { PublishMessage(cross(cur), 0, nil, 1) }) }
	setMessageFee([32]byte{1}, feePayload(wormholeChainID, word(2)), wormholeChainID, coreAddress)
	pay(2, "ugnot")
	if got := publish(); got != "" {
		t.Fatalf("paid: %q", got)
	}
	sink := chain.PackageAddress("gno.land/r/wormhole_test/sink")
	transferFees(cur, [32]byte{2}, payoutPayload(0, word(uint64(balance(coreAddress))), field(t, sink)), wormholeChainID)
	if balance(coreAddress) != 0 || recordedBalance != 0 {
		t.Errorf("balance %d, record %d after paying everything out", balance(coreAddress), recordedBalance)
	}
	if got := publish(); got != "fee-unpaid" {
		t.Errorf("unpaid after the payout: %q", got)
	}
	pay(2, "ugnot")
	if got := publish(); got != "" {
		t.Errorf("paid after the payout: %q", got)
	}
}

// TestPublishFeeUnpaid: with a fee of 3 ugnot, a publication is refused with
// fee-unpaid when unpaid, underpaid, or paid in another denomination, and
// uses no sequence. Paid in full, it is accepted and records the balance, so
// the next one pays again.
func TestPublishFeeUnpaid(cur realm, t *testing.T) {
	reset()
	messageFee = 3
	path := "gno.land/r/wormhole_test/a"
	emitter := decoded(t, chain.PackageAddress(path))
	testing.SetRealm(testing.NewCodeRealm(path))
	publish := func() string { return abort(func() { PublishMessage(cross(cur), 0, nil, 1) }) }
	if got := publish(); got != "fee-unpaid" {
		t.Errorf("unpaid: %q", got)
	}
	pay(2, "ugnot")
	if got := publish(); got != "fee-unpaid" {
		t.Errorf("underpaid: %q", got)
	}
	pay(3, "uatom")
	if got := publish(); got != "fee-unpaid" {
		t.Errorf("paid in uatom: %q", got)
	}
	if NextSequence(emitter) != 0 {
		t.Error("a refused publication used a sequence")
	}
	pay(1, "ugnot")
	if got := publish(); got != "" {
		t.Fatalf("paid: %q", got)
	}
	if NextSequence(emitter) != 1 || recordedBalance != balance(coreAddress) {
		t.Error("the paid publication")
	}
	if got := publish(); got != "fee-unpaid" {
		t.Errorf("the next, unpaid: %q", got)
	}
}

// TestPublishFeeOverpaid: an overpayment is accepted and stays in Core as
// collected fees; it pays no later publication.
func TestPublishFeeOverpaid(cur realm, t *testing.T) {
	reset()
	messageFee = 2
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/b"))
	publish := func() string { return abort(func() { PublishMessage(cross(cur), 0, nil, 1) }) }
	pay(7, "ugnot")
	held := balance(coreAddress)
	if got := publish(); got != "" {
		t.Fatalf("overpaid: %q", got)
	}
	if got := publish(); got != "fee-unpaid" {
		t.Errorf("the next, unpaid: %q", got)
	}
	if balance(coreAddress) != held || recordedBalance != held {
		t.Error("the overpayment did not stay as collected fees")
	}
}

// TestPublishFeeZero: at fee 0 a publication needs no payment and leaves the
// record alone. Coins sent meanwhile pay no later fee: SetMessageFee records
// the balance the new fee is paid from.
func TestPublishFeeZero(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/c"))
	publish := func() string { return abort(func() { PublishMessage(cross(cur), 0, nil, 1) }) }
	recorded := recordedBalance
	pay(5, "ugnot")
	if got := publish(); got != "" {
		t.Fatalf("at fee 0: %q", got)
	}
	if recordedBalance != recorded {
		t.Error("the publication at fee 0 wrote the record")
	}
	setMessageFee([32]byte{1}, feePayload(wormholeChainID, word(1)), wormholeChainID, coreAddress)
	if recordedBalance != balance(coreAddress) {
		t.Error("SetMessageFee did not record the balance")
	}
	if got := publish(); got != "fee-unpaid" {
		t.Errorf("coins sent at fee 0 paid the new fee: %q", got)
	}
}

// TestPublishFeeNeverWraps: a record above the balance is refused, never
// read as a payment, and a fee at the int64 maximum is compared at full
// width. Core publishes as itself, so the test can pay its coins back out.
func TestPublishFeeNeverWraps(cur realm, t *testing.T) {
	reset()
	asCore(t, cur)
	publish := func() string { return abort(func() { PublishMessage(cross(cur), 0, nil, 1) }) }
	messageFee = 1
	recordedBalance = balance(coreAddress) + 1
	if got := publish(); got != "fee-unpaid" {
		t.Errorf("record above the balance: %q", got)
	}
	// Core holds the int64 maximum, recorded at 1 and then at 0.
	const max = 1<<63 - 1
	start := balance(coreAddress)
	pay(max-start, "ugnot")
	messageFee = max
	recordedBalance = 1
	if got := publish(); got != "fee-unpaid" {
		t.Errorf("one short of the maximum: %q", got)
	}
	recordedBalance = 0
	if got := publish(); got != "" {
		t.Errorf("the maximum, paid: %q", got)
	}
	if recordedBalance != max {
		t.Errorf("record %d", recordedBalance)
	}
	sink := chain.PackageAddress("gno.land/r/wormhole_test/sink-max")
	transferFees(cur, [32]byte{0xee}, payoutPayload(0, word(max-uint64(start)), field(t, sink)), wormholeChainID)
	if balance(coreAddress) != start {
		t.Errorf("balance %d after paying the test's coins out, want %d", balance(coreAddress), start)
	}
}

// TestPublishCheckOrder: the fee step runs after the ephemeral and size
// checks and before the address decode and the sequence. A publication
// refused after the fee step leaves the record, so its payment still counts.
func TestPublishCheckOrder(cur realm, t *testing.T) {
	reset()
	messageFee = 1
	user := chain.PackageAddress("gno.land/r/wormhole_test/user")
	publish := func(n int) string { return abort(func() { PublishMessage(cross(cur), 0, make([]byte, n), 1) }) }
	testing.SetRealm(runtime.NewRealm(user, "gno.land/e/"+string(user)+"/run"))
	if got := publish(0); got != "publisher-ephemeral" {
		t.Errorf("ephemeral, unpaid: %q", got)
	}
	path := "gno.land/r/wormhole_test/full"
	testing.SetRealm(testing.NewCodeRealm(path))
	if got := publish(2_049); got != "payload-too-large" {
		t.Errorf("2,049 bytes, unpaid: %q", got)
	}
	emitter := decoded(t, chain.PackageAddress(path))
	sequences.Set(string(emitter[:]), &seqCell{next: ^uint64(0)})
	if got := publish(0); got != "fee-unpaid" {
		t.Errorf("sequence exhausted, unpaid: %q", got)
	}
	testing.SetRealm(testing.NewUserRealm("g1bg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"))
	if got := publish(0); got != "fee-unpaid" {
		t.Errorf("malformed address, unpaid: %q", got)
	}
	pay(1, "ugnot")
	recorded := recordedBalance
	if got := publish(0); got != "publisher-address-malformed" {
		t.Errorf("malformed address, paid: %q", got)
	}
	if recordedBalance != recorded {
		t.Error("the refused publication wrote the record")
	}
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/wormhole_test/d"))
	if got := publish(0); got != "" {
		t.Errorf("the payment did not count after the refusal: %q", got)
	}
}

// TestFeeTargetChain runs both fee actions on Wormhole chain 0x0102, whose two
// bytes differ, unlike the test configuration's 65535: each reads its target
// chain big-endian. SetMessageFee takes this chain only, TransferFees this
// chain or 0, and a refusal changes nothing.
func TestFeeTargetChain(cur realm, t *testing.T) {
	to := field(t, feeRecipient)
	for target, want := range map[uint16][2]string{
		0x0102: {"", ""},
		0:      {"governance-wrong-target-chain", ""},
		0x0201: {"governance-wrong-target-chain", "governance-wrong-target-chain"},
		0xffff: {"governance-wrong-target-chain", "governance-wrong-target-chain"},
	} {
		reset()
		asCore(t, cur)
		recorded := refusalBaseline()
		if got := abort(func() {
			setMessageFee([32]byte{1}, feePayload(target, word(3)), 0x0102, coreAddress)
		}); got != want[0] {
			t.Errorf("SetMessageFee to %#04x: %q, want %q", target, got, want[0])
		}
		if want[0] != "" && (messageFee != 7 || recordedBalance != recorded || consumed.Size() != 0) {
			t.Errorf("SetMessageFee to %#04x changed state", target)
		}
		reset()
		recorded = refusalBaseline()
		if got := abort(func() {
			transferFees(cur, [32]byte{2}, payoutPayload(target, word(0), to), 0x0102)
		}); got != want[1] {
			t.Errorf("TransferFees to %#04x: %q, want %q", target, got, want[1])
		}
		if want[1] != "" && (messageFee != 7 || recordedBalance != recorded || consumed.Size() != 0) {
			t.Errorf("TransferFees to %#04x changed state", target)
		}
	}
	reset()
}

// TestFeeActionCheckOrder breaks two rules of a fee action at once: the
// length comes first, then the target, the range, the recipient and the
// balance.
func TestFeeActionCheckOrder(cur realm, t *testing.T) {
	reset()
	asCore(t, cur)
	held := balance(coreAddress)
	recorded := refusalBaseline()
	other := uint16(2)
	to := field(t, feeRecipient)
	high := field(t, feeRecipient)
	high[0] = 1
	tooBig := word(0)
	tooBig[24] = 0x80
	for _, c := range []struct {
		name, want string
		fn         func()
	}{
		{"fee: short and another chain", "governance-malformed", func() {
			setMessageFee([32]byte{1}, feePayload(other, word(1))[:33], wormholeChainID, coreAddress)
		}},
		{"fee: all chains and out of range", "governance-wrong-target-chain", func() {
			setMessageFee([32]byte{1}, feePayload(0, tooBig), wormholeChainID, coreAddress)
		}},
		{"payout: long and another chain", "governance-malformed", func() {
			transferFees(cur, [32]byte{1}, append(payoutPayload(other, word(0), to), 0), wormholeChainID)
		}},
		{"payout: another chain and out of range", "governance-wrong-target-chain", func() {
			transferFees(cur, [32]byte{1}, payoutPayload(other, tooBig, to), wormholeChainID)
		}},
		{"payout: out of range and a high recipient byte", "governance-fee-out-of-range", func() {
			transferFees(cur, [32]byte{1}, payoutPayload(0, tooBig, high), wormholeChainID)
		}},
		{"payout: a high recipient byte and above the balance", "governance-fee-recipient", func() {
			transferFees(cur, [32]byte{1}, payoutPayload(0, word(uint64(held)+1), high), wormholeChainID)
		}},
	} {
		if got := abort(c.fn); got != c.want {
			t.Errorf("%s: %q, want %q", c.name, got, c.want)
		}
	}
	if messageFee != 7 || recordedBalance != recorded {
		t.Error("a fee action refused twice over changed the fee or the record")
	}
	messageFee = 0
	unchanged(t, "a fee action refused twice over")
}

// TestRenderShowsFee: Render shows the message fee.
func TestRenderShowsFee(t *testing.T) {
	reset()
	messageFee = 25
	if !strings.Contains(Render(""), "- Message fee: 25 ugnot\n") {
		t.Errorf("%q", Render(""))
	}
	reset()
}
