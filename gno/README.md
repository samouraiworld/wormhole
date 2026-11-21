# Wormhole on gno.land

This folder holds the Wormhole contracts for gno.land, written in Gno, the
Go-like language of gno.land's smart contracts. On gno.land a realm, under
`gno.land/r/`, is a contract with state, and a package, under `gno.land/p/`,
is a stateless library.

# Project structure

| Folder | Module path | What it is |
|---|---|---|
| `wormhole` | `gno.land/r/wormhole/core` | Core: the guardian sets, VAA verification, Core governance and message publication |
| `wormhole/vaa` | `gno.land/p/wormhole/vaa/v0` | VAA parsing and signature checks |
| `token_bridge` | `gno.land/r/wormhole/tokenbridge` | the token bridge's vault |
| `token_bridge/logic/v1` | `gno.land/r/wormhole/tokenbridge/logic/v1` | the token bridge's first logic realm |
| `token_bridge/lib` | `gno.land/p/wormhole/tokenbridge/v0` | the token bridge's wire formats |
| `testdata` | | the test corpora, the variant filetests and the test-only realms |
| `scripts` | | the test runner |

A module's path comes from its `gnomod.toml`, not from its folder. Deploying
at these paths needs the `wormhole` namespace on the target network.

Every realm rejects by panicking with its prefix, `core: ` or `tokenbridge: `,
followed by a reason code, and runs every check before its first write.

# Core

Core holds the guardian sets, verifies VAAs for other realms, applies Core
governance and publishes messages for the guardians to observe. It has no
administrator, setter, pause or upgrade path, and its message fee starts at 0.

- `VerifyVAA(raw)` returns the VAA when its guardian set is known and
  unexpired, its signatures reach a quorum of that set, and its payload is
  within Core's bound. A realm consuming VAAs keeps its own replay
  protection.
- `PublishMessage(cur, nonce, payload, consistency)` publishes up to 2,048
  bytes of payload from its caller, a realm or a user, whose address is the
  emitter, and returns its sequence. While there is a message fee, the
  publisher pays it in ugnot to Core's address earlier in the same
  transaction. A `maketx run` script can't publish.
- `SubmitGovernance(cur, raw)` applies a Core governance VAA. It must be
  signed by the current guardian set, come from the governance emitter (chain
  1, `0x00…04`) and not have been applied before. The actions are:
  - 2, guardian-set upgrade, targeting gno.land or every chain. The new set
    becomes current, and the one it replaces expires 24 hours later.
  - 3, `SetMessageFee`, targeting gno.land.
  - 4, `TransferFees`, targeting gno.land or every chain. The recipient's
    first 12 bytes are zero, and its last 20 are the gno address paid.

  Any other action fails with `governance-unsupported-action`: Core is never
  upgraded (action 1), and the token bridge confirms chain IDs itself
  (action 5).
- The reads are `GuardianSet`, `CurrentGuardianSetIndex`,
  `GovernanceConsumed`, `NextSequence`, `MessageFee`, `ChainID`, `GnoChainID`
  and `Render`.

Core's reason codes: `malformed`, `unknown-guardian-set`,
`guardian-set-expired`, `signature-count-exceeds-set`, `no-quorum`,
`recovery-id-out-of-range`, `signature-index-not-ascending`,
`signature-index-out-of-range`, `invalid-signature`, `duplicate-signer`,
`governance-not-current-set`, `governance-wrong-chain`,
`governance-wrong-emitter`, `governance-replay`, `governance-wrong-module`,
`governance-unsupported-action`, `governance-wrong-target-chain`,
`governance-malformed`, `guardian-set-index-not-next`, `guardian-set-empty`,
`guardian-set-zero-key`, `guardian-set-too-large`,
`governance-arithmetic-overflow`, `invalid-configuration`, `wrong-network`,
`publisher-ephemeral`, `payload-too-large`, `publisher-address-malformed`,
`sequence-exhausted`, `fee-unpaid`, `governance-fee-out-of-range`,
`governance-fee-recipient` and `governance-payout-exceeds-balance`.

The VAA package is stateless: it checks signatures against whatever set its
caller passes, so only a VAA that Core's `VerifyVAA` returns is verified.

# Token bridge

The token bridge is two realms.

- The **vault**, `gno.land/r/wormhole/tokenbridge`, never moves: its package
  address is the bridge's emitter. It holds every value and record: the GNOT
  escrow, the wrapped tokens, the peers, the redeemed transfers and their
  claims, and the pause and chain-ID state. It builds every message it
  publishes.
- A **logic** realm decides which inbound transfers the vault pays, to whom
  and when, and which transfers go out, under its allowlist and limits. The
  vault accepts value operations only from the current logic, and guardians
  replace the logic by governance.

## Transfers

- In, through the logic:
  - `Redeem(cur, raw)` takes a transfer from a registered peer, which anyone
    may present. A payload 1 within its asset's inbound budget is paid at
    once, the relayer fee to the caller. A payload 1 over the budget is
    recorded as a claim released 24 hours later, which anyone completes
    through `CompleteClaim` once released.
  - Every payload 3 is recorded as a claim, released at once or, over the
    budget, 24 hours later. Only its recipient completes it, through the
    vault's `CompletePayload`. A body too large for one transaction is
    staged first, in chunks of 65,536 bytes (`StageChunk`, `CommitStaged`,
    `DiscardStaged`).
  - `CreateWrapped(cur, raw)` creates the wrapped token an `AssetMeta` from a
    registered peer describes, if the allowlist opens the asset.
- Out, through the logic:
  - `TransferGNOT` and `TransferGNOTWithPayload` lock GNOT in the vault. Only
    a user calling directly may send GNOT, attaching the amount plus Core's
    message fee.
  - `TransferWrapped` and `TransferWrappedWithPayload` burn a wrapped token
    from the caller, a user or a realm. A realm pays Core's fee itself
    first.
  - `AttestGNOT(cur, nonce)` publishes GNOT's `AssetMeta`.

## Allowlist and limits

The logic seeds these from its configuration, so a new logic changes them.

- Every wrapped asset must be on the allowlist, open or exit-only. An open
  asset is redeemed, wrapped and sent out. An exit-only one only goes out,
  under its outbound limits. GNOT is always open.
- Per asset, outbound: a per-transfer cap and a cap over 24 hours
  (`outbound-cap`).
- Per asset, inbound: a budget over 24 hours. A transfer over it is
  delayed, as above, and counted neither then nor at its release.
- A window counts amounts in 25 hourly buckets of block time, the current
  hour and the 24 before it. A new logic starts with empty windows.

## Governance

The vault checks each token bridge governance VAA itself, as Core checks its
own.

- Action 1, `RegisterChain`: anyone may present it. Its target is gno.land or
  every chain. The peer's chain is neither 0 nor gno.land's, its emitter is not
  zero, and a peer is never replaced.
- Action 2, `Upgrade`: the new logic presents it through its own
  `Activate(cur, raw)`, which anyone may call. The VAA's contract field is
  the new logic's package address. `Activate` doesn't check which logic the
  switch replaces, so request a switch only while the logic it replaces is
  current, and one at a time.
- Action 4, `SetPauserAddresses`: sets the pauser, the freezer and the
  unpauser, each a gno address or none.
- Action 3, chain-ID recovery, has no entry point: the chain-ID confirmation
  below replaces it.

## Pause and chain-ID confirmation

- The pauser's `Pause` stops value operations for 5 days, and the freezer's
  `Freeze` stops them until the unpauser's `Unpause`. Anyone may call
  `UnpauseExpired` once a pause has run out. The roles are unassigned until a
  `SetPauserAddresses` VAA.
- The vault binds the gno chain ID it was deployed under. Under any other,
  value operations fail with `bridge-frozen`. The unpauser proposes the new
  chain ID with `ProposeChainID`; anyone executes it with `ExecuteChainID`
  between 24 and 48 hours later, while the chain ID still equals it; and
  `CancelChainID` withdraws it.

The token bridge's reason codes are in `testdata/tokenbridge-reason-codes.json`.

# Deviations from the EVM contracts

- Core is never upgraded, and handles neither action 1 nor action 5.
- Core governance runs on any gno chain ID, a forked one included. On EVM, a
  fork refuses `SetMessageFee`, and refuses a guardian-set upgrade or a
  `TransferFees` unless it targets every chain.
- A `TransferFees` recipient's first 12 bytes must be zero, where EVM
  truncates.
- The token bridge is a fixed vault and a replaceable logic, and an upgrade
  switches the logic realm.
- A transfer's replay key is its emitter chain, emitter and sequence, not its
  body's digest, so a second body under a redeemed sequence fails.
- Token bridge governance needs the current guardian set, where EVM accepts
  any unexpired one.
- `RegisterChain` refuses emitter chain 0, gno.land's own chain and a zero
  emitter, and a registration targeting gno.land runs on a fork too.
- An `AssetMeta`'s token chain must equal its emitter's chain.
- Only allowlisted assets are wrapped or redeemed, under the limits above.
- Only GNOT is native, where EVM releases any native token.
- Amounts above the `int64` range fail with `amount-out-of-range`, a relayer
  fee's included.
- A wrapped token keeps min(decimals, 8) decimals.
- Anyone may redeem a payload 3, which records a claim that only its
  recipient completes; on EVM only the recipient redeems it.
- Chain-ID confirmation replaces action 3, which EVM accepts on a fork.

# Building and testing

The realms call `crypto/secp256k1.RecoverPubkey`, which a draft gno pull
request adds and gno.land doesn't run yet. The Dockerfile builds gno v1.7.0,
the release gno.land's mainnet runs, with that pull request's standard-library
changes applied.

To run the tests in Docker:

```sh
make test-docker
```

To run them on a machine with Python 3, set `GNOROOT` to such a gno checkout
and put its `gno` on `PATH`:

```sh
make test
```

`scripts/test.py` builds a temporary gno workspace laid out by module path:
the five modules, the gno example packages they import, copied from
`GNOROOT/examples`, and the test-only realms of `testdata/realms`. Each realm's
committed `config.gno` fails closed, so the runner writes a test
configuration in its place, on the public test keys and gno's test chain ID,
`dev`. Then:

- every test and filetest of the five modules must pass, with one generated
  filetest per scenario of the two corpora (`scripts/corpus.py`);
- Core, the vault and the logic run under the configurations their main runs
  can't use: each refusal must fail with its named reason, and each variant
  must pass its filetests from `testdata/core-variant` or
  `testdata/logic-variant`;
- no deployable file may import a test-only realm;
- gno must fetch nothing, so the runner works offline.

The corpora, `testdata/core-vectors.json` and
`testdata/tokenbridge-vectors.json`, come from a reference model of the realms,
checked against Wormhole's Go SDK. Their VAAs are signed with public test keys,
secp256k1 scalars 1 to 19, 101 to 119 and 201 to 219, which are unsafe for
funds. The generated `vectors_test.gno` files are fixtures from the same
source.

# Deploying

Each realm's committed `config.gno` fails closed. A deployment replaces it
with a reviewed configuration that meets these rules; `init` checks only some
of them.

- Core, `wormhole/config.gno`:
  - `wormholeChainID` is the chain ID Wormhole assigns gno.land: never 0, and
    never 65535, which marks gno's test chains;
  - `gnoChainID` is the target network's gno chain ID;
  - `initialSetIndex` and `initialKeys` are a published guardian set, its
    20-byte addresses packed in index order: on mainnet, the canonical set at
    that index. No key may be a public test key or a devnet guardian's;
  - `replayUntilIndex` equals `initialSetIndex`. Above it, each upgrade
    accepted below that index expires the set it replaces at once, for a
    deployment that installs an older set and replays the published upgrades
    after it.
- The vault, `token_bridge/config.gno`: `wormholeChainID` and `gnoChainID`
  equal Core's, and `initialLogic` is the first logic's path.
- The logic, `token_bridge/logic/v1/config.gno`:
  - GNOT's limits, in ugnot, and each asset's, in wire units, are not
    negative;
  - each allowlist entry names a token on a chain other than 0 and gno.land,
    by its 32-byte address in hex, once;
  - an exit-only asset's outbound limits are above 0, since it may only go
    out. An outbound limit of 0 on an open asset or GNOT stops it going out;
  - a later logic keeps every asset the current one lists, open or
    exit-only: an asset it drops could no longer leave.

Deploy the VAA package and Core, then the token bridge's package, the vault
and the first logic, and register each peer with its `RegisterChain` VAA.

# Limits

- gno.land's Wormhole chain ID in the SDK, 900, is a placeholder for this
  fork until Wormhole assigns one; no network should use it.
- gno.land needs `crypto/secp256k1.RecoverPubkey` before these realms can be
  deployed, and they are deployed on no public gno network. Deploying at
  `gno.land/{p,r}/wormhole/...` needs the `wormhole` namespace on the target
  network.
- No test here runs the realms on a gno.land node, measures their costs, or
  checks that every reason code has a test.
- The filetests' gas and storage figures hold for the gno the Dockerfile
  builds.
