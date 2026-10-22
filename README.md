# Mutually Assured Destruction (MAD)

`src/MADToken.sol:MADToken` is a fixed supply ERC-20. It mints the entire supply once,
to the address that deploys it. The contract uses the vendored OpenZeppelin Contracts
v5.0.2 ERC-20 implementation without overriding its transfer or allowance behavior.

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `MADToken` |
| Token name | `Mutually Assured Destruction` |
| Symbol | `MAD` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Native currency required by constructor | `0` |
| Initial recipient | Constructor `msg.sender` |
| Administrative roles | None |
| Target launch chain | Ethereum, chain ID `1` |

## Behavior and assumptions

The brief specifies the name, symbol, decimals, supply, and initial recipient. The
name is branding; it does not introduce a destruction mechanism. MAD uses ordinary
ERC-20 transfers and approvals, with no fees, burns, rebasing, pause, blacklist,
ownership, upgrade mechanism, or additional minting entry point. `INITIAL_SUPPLY`
is the named constant representing the supply in smallest units.

- Transfers deliver the exact amount and keep total supply constant. Self-transfers
  preserve balances. Transfers of zero are allowed and emit `Transfer`.
- Transfers to the zero address revert, including transfers of zero. Insufficient
  balances or allowances revert with ERC-6093 custom errors; failed calls roll back
  all balance and allowance changes.
- `approve` replaces the caller's allowance and emits `Approval`. A spender can
  move tokens only within that allowance. `transferFrom` reduces finite allowances;
  `type(uint256).max` is an unlimited allowance and is not reduced. OpenZeppelin
  v5 does not emit `Approval` when `transferFrom` consumes allowance, so integrations
  should read `allowance` when they need its current value.
- Transfers do not invoke recipient callbacks. A recipient contract must provide
  its own way to use or return received tokens.
- There is no payable entry point, token recovery function, proxy, external library
  link, oracle, or external contract call in the token or its constructor.

## Build and check

Run from the repository root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x69f78fb2570b1118586e2fed90e34a848bd2bf0b9b1488869ff3e15962f071ee forge test
forge fmt --check
```

The project pins the compiler by version, targets Cancun, enables the optimizer
with 200 runs, and sets `bytecode_hash = "none"`. All imported Solidity dependencies
and their licenses are ordinary files under `lib/`; no install step, submodule,
RPC connection, environment secret, FFI, or filesystem cheatcode permission is
required. The verifier supplies the pinned compiler for offline builds.
Dependency provenance and file checksums are in `lib/README.md` and `lib/SHA256SUMS`.

Tests include direct and CREATE2 factory deployments, the mint event, exact launch
distribution and claim transfers, transfers in both directions with a pool manager
fixture, ERC-20 success and failure cases, events, approval replacement/revocation,
unlimited approval, rollback on failure, unsupported privileged calls, and fuzzed
amounts and recipients. Stateful invariants model four holders through randomized
transfers, approvals, delegated spending, overdrafts, and invalid recipients,
checking supply conservation, exact balances, and allowances. Defaults are 512
runs per fuzz test and 128 sequences of 64 calls per invariant. Tests use isolated
local fixtures and do not read or change environment variables.

The local pool manager fixture checks token movement only; it does not execute
Uniswap swaps. The supplied protected launch harness requires the network's launch
infrastructure and resolved deployment values, so full pool seeding and swap checks
remain with that harness. Local test fixtures are not deployment contracts.

## Deployment and launch responsibilities

The launch system deploys the creation bytecode for `MADToken` without appended
constructor arguments. Its artifact is `out/MADToken.sol/MADToken.json`. The
factory receives all `10^27` smallest units because it is the constructor's caller;
the caller of the factory receives nothing directly from the constructor. This is
intentional. No token is allocated to the token contract or any application contract.
Only `MADToken` is delivered under `src/`.

The launch system supplies the factory address and CREATE2 salt, writes the launch
manifest in its subsequent step, distributes tokens, initializes and seeds the pool,
and verifies deployed source/bytecode. The token needs no factory, pool manager,
distributor, owner, or recipient address configured beforehand. The factory has
ordinary holder rights over its initial balance and no continuing privilege over
other holders. No transactions are broadcast by this project.

The task's launch allocation is 10% (100,000,000 MAD) for the swarm's distributor,
80% (800,000,000 MAD) for the pool, and the remaining 10% (100,000,000 MAD) for
`0x6bf192ebef135e0f645e99d59d9bf44e7711606c`. These are factory operations; the
token constructor does not distribute those shares. The launch terms also specify:

| External launch parameter | Task-provided value |
| --- | --- |
| Paired token | FWA at `0xa0df17b5ac76ababa36e1450e2cbcd18a620c845` (18 decimals) |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Recorded initial price | `79228162514264337593543950336` (provenance only) |
| Initial market cap in FWA smallest units | `2000000000000000000000000` (2,000,000 FWA) |

The factory derives the actual pool opening price from the launch economics and
token ordering. None of these external launch settings adds a token transfer tax
or requires an exemption in MAD.

## After launch

No initialization, setters, administrator, keeper, or ongoing maintenance service is
required. The launch operator should confirm name, symbol, decimals, supply, factory
distribution, and deployed bytecode against the accepted build and complete the
network's independent review and source verification before release.

Holders control transfers and approvals. They should approve only trusted spenders
for needed amounts and revoke unused allowances. Replacing a live allowance can
race with a spender using its old value; a wallet can first set it to zero, wait
for confirmation, then approve the replacement. Unlimited approval remains live
until revoked. There is no administrator who can recover mistaken transfers,
restore a lost key, recover assets sent to the token contract, freeze an attacker,
or alter the supply. Native currency forcibly sent to the token also has no
withdrawal path.

The included tests and source review cover this small token's behavior; they are
not an independent security audit. No oracle, randomness, signature, vault,
external-call reentrancy, or upgrade subsystem is present. Slither and Mythril are
not part of the recorded local checks.
