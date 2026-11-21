package tokenbridge

// The wrapped-token functions, after grc20factory. Each acts as its
// caller on the token's ledger and panics with grc20's own error text when
// the ledger refuses. They stay open while paused and under the chain-ID
// freeze: gating them would not stop wrapped balances moving, since
// grc20reg's functions move them too, and they move no escrow and mint
// nothing.

// Transfer sends amount of the wrapped token symbol from the caller to to.
func Transfer(cur realm, symbol string, to address, amount int64) {
	w := requireWrapped(symbol)
	if err := w.ledger.Transfer(cur.Previous().Address(), to, amount); err != nil {
		panic(err.Error())
	}
	lapse()
}

// Approve lets spender move up to amount of the caller's symbol.
func Approve(cur realm, symbol string, spender address, amount int64) {
	w := requireWrapped(symbol)
	if err := w.ledger.Approve(cur.Previous().Address(), spender, amount); err != nil {
		panic(err.Error())
	}
	lapse()
}

// TransferFrom moves amount of from's symbol to to, as the caller, from
// from's allowance to it.
func TransferFrom(cur realm, symbol string, from, to address, amount int64) {
	w := requireWrapped(symbol)
	if err := w.ledger.TransferFrom(from, cur.Previous().Address(), to, amount); err != nil {
		panic(err.Error())
	}
	lapse()
}

func requireWrapped(symbol string) *wrappedAsset {
	w := wrappedBySymbol(symbol)
	if w == nil {
		panic("tokenbridge: wrapped-not-found")
	}
	return w
}
