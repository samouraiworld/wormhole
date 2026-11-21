"""The corpus-scenario filetests: one filetest per scenario of the two corpora.

testdata/core-vectors.json and testdata/tokenbridge-vectors.json hold VAAs
signed with public test keys and, for each step of each scenario, the outcome
the realms must give. test.py writes the filetests generated here into Core's
and the logic's filetests directories before their runs, so they are never
committed and cannot drift from the corpora.
"""

# The Core corpus's step ops, each naming the Core entry point it calls.
CORE_OPS = ("verify", "governance")

# The token bridge corpus's ops that present a VAA or need only a caller, each
# with its call, and the ones the filetest carries out itself. {logic} is the
# current logic realm's alias in the generated filetest.
TB_CALLS = {"redeem": "{logic}.Redeem(cross(cur), raw)",
            "create_wrapped": "{logic}.CreateWrapped(cross(cur), raw)",
            "governance": "tokenbridge.RegisterChain(cross(cur), raw)",
            "set_pauser_addresses": "tokenbridge.SetPauserAddresses(cross(cur), raw)",
            "core_governance": "core.SubmitGovernance(cross(cur), raw)",
            "pause": "tokenbridge.Pause(cross(cur))",
            "freeze": "tokenbridge.Freeze(cross(cur))",
            "unpause": "tokenbridge.Unpause(cross(cur))",
            "unpause_expired": "tokenbridge.UnpauseExpired(cross(cur))",
            "propose_chain_id": "tokenbridge.ProposeChainID(cross(cur))",
            "cancel_chain_id": "tokenbridge.CancelChainID(cross(cur))",
            "execute_chain_id": "tokenbridge.ExecuteChainID(cross(cur))"}
TB_HARNESS_OPS = ("set_runtime_chain_id", "allowlist_add", "allowlist_remove", "lock", "donate")

# The token bridge's first logic realm, which every scenario starts from.
LOGIC = "gno.land/r/wormhole/tokenbridge/logic/v1"


class CorpusError(Exception):
    pass


def filetest_name(scenario):
    """The name of a corpus scenario's filetest."""
    return "zcorpus_" + scenario.replace("-", "_") + "_filetest.gno"


def core_filetest(scenario):
    """The filetest of a Core corpus scenario: each step prints its outcome, the
    current guardian set and the message fee."""
    calls, expected = [], []
    for step in scenario["steps"]:
        if step["op"] not in CORE_OPS:
            raise CorpusError(f"Core corpus scenario {scenario['name']}: op {step['op']!r} is none of "
                              f"{', '.join(CORE_OPS)}")
        calls.append(f'\tstep("{step["op"]}", {step["time"]}, "{step["vaa_hex"]}")')
        result = "accept" if step["expect"] == "accept" else "reject core: " + step["reason"]
        expected.append(f'// {result} {step["current_guardian_set_after"]} {step["message_fee_after"]}')
    newline = "\n"
    return f"""// PKGPATH: gno.land/r/wormhole_test/corpus
package corpus

// Generated from the Core test corpus, scenario {scenario["name"]}: each step
// prints its outcome, the current set and the message fee.

import (
	"encoding/hex"
	"testing"
	"time"

	"gno.land/r/wormhole/core"
)

func main(cur realm) {{
	step := func(op string, at int64, wire string) {{
		ctx := testing.GetContext()
		ctx.Time = time.Unix(at, 0)
		testing.SetContext(ctx)
		raw, err := hex.DecodeString(wire)
		if err != nil {{
			panic(err)
		}}
		r := revive(func() {{
			switch op {{
			case "verify":
				core.VerifyVAA(raw)
			case "governance":
				core.SubmitGovernance(cross(cur), raw)
			default:
				panic("unknown op " + op)
			}}
		}})
		if r == nil {{
			println("accept", core.CurrentGuardianSetIndex(), core.MessageFee())
		}} else {{
			println("reject", r, core.CurrentGuardianSetIndex(), core.MessageFee())
		}}
	}}
{newline.join(calls)}
}}

// Output:
{newline.join(expected)}
"""


def vaa_payload(raw):
    """The payload of an accepted step's VAA: the bytes after its signatures and
    its 51-byte body header."""
    return raw[6 + 66 * raw[5] + 51:]


# The helpers of each generated token bridge corpus filetest.
TB_CORPUS_HELPERS = """const vaultPath = "gno.land/r/wormhole/tokenbridge"

// addr is a 20-byte caller in hex as an address; "" is the presenter, who
// calls the steps that name no caller, an address the corpus never uses.
func addr(h string) address {
	if h == "" {
		return chain.PackageAddress("gno.land/r/wormhole_test/presenter")
	}
	s, err := bech32.EncodeFromBase256("g", wire(h))
	if err != nil {
		panic(err)
	}
	return address(s)
}

func wire(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return b
}

// at makes who the current realm of the frame that calls it, so that the next
// crossing call from there sees who as its cur.Previous(), at a block time and
// chain ID, under an origin caller the corpus never uses. Called anywhere but
// directly from main, it would miss main's cur.
func at(unix int64, chainID string, who runtime.Realm) {
	ctx := testing.GetContext()
	ctx.CurrentRealm = who
	ctx.OriginCaller = chain.PackageAddress("gno.land/r/wormhole_test/origin")
	ctx.Time = time.Unix(unix, 0)
	ctx.ChainID = chainID
	testing.SetContext(ctx)
}

func outcome(r any) string {
	if r == nil {
		return "accept"
	}
	return "reject " + r.(string)
}

func unchanged(before, after string) string {
	if before == after {
		return "unchanged"
	}
	return "CHANGED\\n" + before + "\\n---\\n" + after
}

func bank(a address) int64 {
	return banker.NewReadonlyBanker().GetCoin(a, "ugnot")
}

// issue gives the vault ugnot, as the logic's send before a lock does.
func issue(amount int64) {
	testing.IssueCoins(chain.PackageAddress(vaultPath), chain.NewCoins(chain.NewCoin("ugnot", amount)))
}

func held(tokenChain uint16, token string, a address) int64 {
	return tokenbridge.BalanceOf(tokenbridge.WrappedSymbol(tokenChain, token), a)
}

func decimalsOf(tokenChain uint16, token string) int {
	return grc20reg.Get(vaultPath + "." + tokenbridge.WrappedSymbol(tokenChain, token)).GetDecimals()
}

// body returns a VAA's body, or nil if raw is too short to hold its header.
func body(raw []byte) []byte {
	if len(raw) < 6 || len(raw) < 6+66*int(raw[5])+51 {
		return nil
	}
	return raw[6+66*int(raw[5]):]
}

func digestOf(b []byte) [32]byte {
	h := keccak256.Sum256(b)
	return keccak256.Sum256(h[:])
}

// claimLine shows, for the VAA with this body, its claim, or none, and whether
// its replay key is recorded.
func claimLine(b []byte) string {
	var sequence uint64
	for _, c := range b[42:50] {
		sequence = sequence<<8 | uint64(c)
	}
	emitterChain, emitter := uint16(b[8])<<8|uint16(b[9]), hex.EncodeToString(b[10:42])
	redeemed := strconv.FormatBool(tokenbridge.IsRedeemed(emitterChain, emitter, sequence))
	found, id, recipient, assetChain, asset, amount, fee, n, digest, release, delayed, state :=
		tokenbridge.Claim(emitterChain, emitter, sequence)
	if !found {
		return "none " + redeemed
	}
	_, to, err := bech32.DecodeToBase256(recipient)
	if err != nil {
		panic(err)
	}
	d := digestOf(b)
	return strconv.Itoa(id) + " " + hex.EncodeToString(to) + " " + strconv.Itoa(assetChain) + " " + asset + " " +
		strconv.FormatInt(amount, 10) + " " + strconv.FormatInt(fee, 10) + " " + strconv.Itoa(n) + " " +
		strconv.FormatInt(release, 10) + " " + strconv.FormatBool(delayed) + " " + state + " " +
		strconv.FormatBool(digest == hex.EncodeToString(d[:])) + " " + redeemed
}

// state shows what a rejected step must leave as it was: the vault's and the
// current logic's pages, Core's set and fee, the ugnot of the caller and the
// vault and, for the VAA a step presents, its claim, its replay key and its
// governance digest and, for a transfer, what its recipient and caller hold.
func state(render func(string) string, raw []byte, caller address) string {
	s := tokenbridge.Render("") + render("") + strconv.Itoa(int(core.CurrentGuardianSetIndex())) + " " +
		strconv.FormatInt(core.MessageFee(), 10) + " " + strconv.FormatInt(bank(caller), 10) + " " +
		strconv.FormatInt(bank(chain.PackageAddress(vaultPath)), 10)
	b := body(raw)
	if b == nil {
		return s
	}
	d := digestOf(b)
	s += " " + claimLine(b) + " " + strconv.FormatBool(tokenbridge.GovernanceConsumed(hex.EncodeToString(d[:]))) +
		" " + strconv.FormatBool(core.GovernanceConsumed(d))
	p := b[51:]
	if len(p) >= 101 && (p[0] == 1 || p[0] == 3) {
		to, err := bech32.EncodeFromBase256("g", p[79:99])
		if err != nil {
			panic(err)
		}
		tokenChain, token := uint16(p[65])<<8|uint16(p[66]), hex.EncodeToString(p[33:65])
		s += " " + strconv.FormatInt(bank(address(to)), 10) + " " +
			strconv.FormatInt(held(tokenChain, token, address(to)), 10) + " " +
			strconv.FormatInt(held(tokenChain, token, caller), 10)
	}
	return s
}
"""


def tokenbridge_filetest(scenario, corpus, bridge_codes):
    """The filetest of a token bridge corpus scenario, and the logic copies its
    allowlist steps switch to: path -> (the open entries, the exit-only ones).
    Removing an asset from the allowlist makes it exit-only.

    Each step runs from main under its time, runtime chain ID and caller, and
    prints its outcome. An accepted step also prints its payouts, its claim or
    its decimals, and a rejected one whether it left the state unchanged, since
    revive keeps the writes of a refused call. The last line holds the escrow and
    the vault's ugnot, which the steps determine. A rejection's reason is the
    token bridge's when bridge_codes lists it, and Core's otherwise or for a
    step that calls Core.
    """
    name = scenario["name"]
    gnot = (corpus["chain_id"], corpus["gnot_token_address"])
    chain_id, allowlist, exit_only, peer = corpus["gno_chain_id"], list(corpus["allowlist"]), [], None
    alias, current = "l0", LOGIC
    imports, copies, calls, expected = [(alias, current)], {}, [], []
    locked, banked = 0, 0
    for index, step in enumerate(scenario["steps"]):
        op = step["op"]
        at_time = step["time"]
        lines, outcome = [], "accept"
        if op not in TB_CALLS and op not in TB_HARNESS_OPS:
            raise CorpusError(f"Corpus scenario {name}: op {op!r} is none of "
                              f"{', '.join((*TB_CALLS, *TB_HARNESS_OPS))}")
        if step["expect"] not in ("accept", "reject") or (op in TB_HARNESS_OPS and step["expect"] != "accept"):
            raise CorpusError(f"Corpus scenario {name}: step {index} ({op}) expects {step['expect']!r}")
        if op == "set_runtime_chain_id":
            chain_id = step["gno_chain_id"]
            lines, outcome = [f'println("{index} chain {chain_id}")'], f"chain {chain_id}"
        elif op in ("allowlist_add", "allowlist_remove"):
            origin = step["origin"]
            allowlist = [o for o in allowlist if o != origin] + ([origin] if op == "allowlist_add" else [])
            exit_only = [o for o in exit_only if o != origin] + ([origin] if op == "allowlist_remove" else [])
            current, alias = step["logic"], f"l{len(imports)}"
            copies[current] = (list(allowlist), list(exit_only))
            imports.append((alias, current))
            lines = [f'at({at_time}, "{chain_id}", testing.NewUserRealm(addr("")))',
                     f'{alias}.Activate(cross(cur), wire("{step["vaa_hex"]}"))',
                     f"render = {alias}.Render",
                     f'println("{index}", tokenbridge.Logic())']
            outcome = current
        elif op == "lock":
            if peer is None:
                raise CorpusError(f"Corpus scenario {name}: lock step {index} has no registered peer")
            amount = step["amount"]
            lines = [f'at({at_time}, "{chain_id}", testing.NewCodeRealm("{current}"))', f"issue({amount})",
                     f'tokenbridge.LockAndPublish(cross(cur), addr(""), {amount}, {peer}, [32]byte{{31: 0xee}}, 0, 0)',
                     f'println("{index} locked")']
            outcome = "locked"
            locked, banked = locked + amount, banked + amount
        elif op == "donate":
            lines = [f'issue({step["amount"]})', f'println("{index} donated")']
            outcome = "donated"
            banked += step["amount"]
        else:
            caller, raw = step.get("caller", ""), bytes.fromhex(step.get("vaa_hex", ""))
            lines = [f'at({at_time}, "{chain_id}", testing.NewUserRealm(addr("{caller}")))',
                     f'raw = wire("{raw.hex()}")']
            revived = f"r = revive(func() {{ {TB_CALLS[op].format(logic=alias)} }})"
            if step["expect"] == "reject":
                prefix = "core: " if op == "core_governance" or step["reason"] not in bridge_codes else "tokenbridge: "
                lines += [f'before = state(render, raw, addr("{caller}"))', revived,
                          f'println("{index}", outcome(r), unchanged(before, state(render, raw, addr("{caller}"))))']
                outcome = f"reject {prefix}{step['reason']} unchanged"
            elif op == "redeem":
                payload = vaa_payload(raw)
                token = int.from_bytes(payload[65:67], "big"), payload[33:65].hex()
                recipient, amount = payload[79:99].hex(), int.from_bytes(payload[1:33], "big")
                holding = "bank({})" if token == gnot else f'held({token[0]}, "{token[1]}", {{}})'
                to_holding, by_holding = holding.format(f'addr("{recipient}")'), holding.format(f'addr("{caller}")')
                lines += [f"to, by = {to_holding}, {by_holding}", revived,
                          f'println("{index}", outcome(r), {to_holding}-to, {by_holding}-by, claimLine(body(raw)))']
                if step.get("claim"):
                    outcome = (f"accept 0 0 3 {recipient} {token[0]} {token[1]} {amount} 0 {51 + len(payload)} "
                               f"{at_time} false open true true")
                else:
                    to_paid, by_paid = step.get("paid_recipient", 0), step.get("paid_relayer", 0)
                    if recipient == caller:  # its one change is the sum of the two
                        to_paid = by_paid = to_paid + by_paid
                    outcome = f"accept {to_paid} {by_paid} none true"
                    if token == gnot:
                        locked, banked = locked - amount, banked - amount
            elif op == "create_wrapped":
                payload = vaa_payload(raw)
                token = int.from_bytes(payload[33:35], "big"), payload[1:33].hex()
                lines += [revived, f'println("{index}", outcome(r), decimalsOf({token[0]}, "{token[1]}"))']
                outcome = f"accept {step['decimals']}"
            else:
                lines += [revived, f'println("{index}", outcome(r))']
                if op == "governance" and peer is None:
                    peer = int.from_bytes(vaa_payload(raw)[35:37], "big")
        calls.extend("\t" + line for line in lines)
        expected.append(f"{index} {outcome}")
    aliases = "\n".join(f'\t{short} "{path}"' for short, path in imports)
    output = "\n".join("// " + line for line in (*expected, f"end {locked} {banked}"))
    newline = "\n"
    text = f"""// PKGPATH: gno.land/r/wormhole_test/corpus
package corpus

// Generated from the token bridge test corpus, scenario {name}.

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"crypto/bech32"
	"crypto/keccak256"
	"encoding/hex"
	"strconv"
	"testing"
	"time"

	"gno.land/r/nt/grc20reg/v0"
	"gno.land/r/wormhole/core"
	"gno.land/r/wormhole/tokenbridge"
{aliases}
)

{TB_CORPUS_HELPERS}
func main(cur realm) {{
	render := l0.Render
	var raw []byte
	var r any
	var before string
	var to, by int64
	_, _, _, _, _, _ = render, raw, r, before, to, by
{newline.join(calls)}
	println("end", tokenbridge.LockedGNOT(), bank(chain.PackageAddress(vaultPath)))
}}

// Output:
{output}
"""
    return text, copies
