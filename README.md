# MINT GAME (MINT)

`src/MintGame.sol:MintGame` is a fixed-supply ERC-20. Its constructor mints
**1,000,000,000 MINT** to the immediate deployer, once. The token uses 18 decimals,
so the total supply in smallest units is **1000000000000000000000000000** (`10^27`).

## Design and assumptions

The brief is interpreted as a standard transferable ERC-20. The contract inherits
the vendored OpenZeppelin ERC20 implementation without overriding transfers,
approvals, or decimals. `INITIAL_SUPPLY` is the named constant for the supply.
Name and symbol are fixed to `MINT GAME` and `MINT` by the constructor.

- All supply initially belongs to `msg.sender`. A factory deployment credits the
  factory, not its caller or transaction origin. No constructor arguments or
  subsequent initialization are needed.
- Transfers move the exact requested amount. There are no token fees, taxes,
  burns, rebases, exemptions, transfer limits, or external callbacks.
- There is no owner, minter, pause, blacklist, seizure, proxy, upgrade, or public
  burn function. The inherited mint/burn helpers are internal; only the
  constructor calls the mint helper. Supply remains constant after deployment.
- Standard ERC-20 zero-value transfers and self-transfers succeed between valid
  addresses. Transfers to the zero address and approvals to a zero spender
  revert. Insufficient balance or allowance reverts with ERC-6093 custom errors.
- Finite allowances decrease on `transferFrom`; `type(uint256).max` denotes an
  unlimited allowance and is not decreased. Even a holder calling `transferFrom`
  on its own balance needs allowance; a direct `transfer` needs none.
- `Transfer` is emitted for minting and successful transfers (including zero
  amounts). `Approval` is emitted for `approve`. OpenZeppelin v5 does not emit
  another `Approval` when `transferFrom` consumes an allowance; clients should
  read `allowance` for its current value.

## Build and test

Run from the repository root with Foundry and Solidity **0.8.26** available:

```sh
forge build
forge test
forge fmt --check
```

The compiler is version-pinned in `foundry.toml`, with Cancun EVM, optimizer enabled
for 200 runs, and `bytecode_hash = "none"`. All Solidity dependencies are ordinary
files under `lib/`, with explicit mappings in `remappings.txt`. There are no
submodules, npm dependencies, RPC calls, forks, or setup downloads. The verifier
supplies the pinned compiler. See [DEPENDENCIES.md](DEPENDENCIES.md) for upstream
versions, archive checksums, and licenses. FFI is disabled and no filesystem
permissions are granted.

The assignment's seed is pinned in the fuzz profile:
`0xa2c5d1515e9c4df99f336118cd0e4fd7d600d8d7357dedf82c81fd82bbc69cab`.
Each fuzz test runs 1,024 cases. Stateful invariants run 256 sequences of up to 64
actions, comparing balances and allowances against an independent ledger after
transfers, approvals, revocations, and attempted unauthorized or excessive spends.
Tests use only isolated local EVM state and do not read or modify environment
variables. Helpers and simulated actors in `test/` are not production contracts
or deployment parameters.

The tests cover constructor metadata and mint event, CREATE2 factory deployment,
exact balance changes, zero/full/self transfers, approval replacement and
revocation, finite/unlimited allowances, revert atomicity, common forbidden admin
entrypoints, and launch allocation/claim/pool token transfers. The local launch
flow test models token movement only; it does not simulate Uniswap pricing or
liquidity settlement. The supplied protected tests require the network's separate
factory/PoolManager harness and manifest inputs and are run by that verifier.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `MintGame` |
| Build artifact | `out/MintGame.sol/MintGame.json` |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Name / symbol | `MINT GAME` / `MINT` |
| Decimals | `18` |
| Total supply, smallest units | `1000000000000000000000000000` |
| Initial recipient | Immediate deploying address (`msg.sender`) |
| Launch chain | Ethereum, chain ID `1` |
| Application contracts | None |

The network deploys the built creation bytecode through its factory. The token's
constructor does not call other contracts or require an existing address, service,
key, owner setting, or oracle. There is no deployment script or broadcast step in
this assignment. `launch.json` belongs to the subsequent manifest step.

The launch's distribution and pool are responsibilities of that factory, not of
the token constructor: 10% (100,000,000 MINT) goes to the network's distributor,
80% (800,000,000 MINT) seeds the pool, and 10% (100,000,000 MINT) goes to
`0x1ee3ffadfe138415a2ddaedeebe5f46616fa413d`.
The paired currency is Ethereum IMD at
`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals). The provided pool policy
is fee `12500` (1.25%) and tick spacing `60`, with an initial whole-supply market
cap of `2500000000000000000000` paired-currency units (2,500 IMD).
The supplied `initialPrice` provenance value is
`79228162514264337593543950336`; the deployer derives the actual opening price
from the market cap, supply, and deployed token address. These launch values are
documented from the assignment and are not embedded as token privileges or fees.

## After launch

No token settings or maintenance transactions are required. The network deployer
is responsible for the manifest, deployment, distribution, liquidity provisioning,
and explorer verification with this exact compiler and configuration. Confirm
the deployed metadata, total supply, and mint recipient before distribution, and
reconcile the transfers and final allocations afterwards.

Holders control their own balances and allowances. Use appropriately limited
approvals and revoke unused ones. When replacing a nonzero allowance, first set
it to zero and confirm that transaction to reduce the standard approval-change
race; a pending revocation cannot undo spending already executed. There is no
administrator to recover mistaken transfers or tokens sent to this contract.
Direct ETH sends revert, and forcibly sent ETH or unrelated tokens cannot be
rescued. Transfers to contracts do not check whether the recipient can later
return them.

The code and tests have been reviewed against the supplied security checklist:
there are no external-call reentrancy paths, price/oracle calculations, signature
authorization, privileged setters, or upgrade paths in this token. Foundry build,
unit/fuzz tests, and stateful invariants are the local checks; Slither/Mythril and
the platform's full launch integration are not claimed as local verification.
An independent adversarial review remains the release process's responsibility;
these tests are not a security audit.
