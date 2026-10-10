# SwarmCore (SWORE)

SwarmCore is a fixed-supply ERC-20 token. Its constructor mints all
1,000,000,000 tokens, each with 18 decimals, to the immediate deployer
(`msg.sender`). No additional tokens can be minted after construction.

## Contract and assumptions

The production contract is [`src/SwarmCore.sol`](src/SwarmCore.sol), built on the
vendored OpenZeppelin Contracts v5.0.2 ERC-20 implementation.

- Name: `SwarmCore`; symbol: `SWORE`; decimals: `18`.
- Supply in smallest units: `1000000000000000000000000000` (`10^27`).
- Transfers deliver exactly the requested amount. There are no taxes, burns,
  rebases, transfer limits, external callbacks, or address exemptions.
- There is no owner, administrator, minter, pause, blacklist, seizure,
  upgrade mechanism, permit extension, or post-deployment initialization.
- `transfer`, `approve`, and `transferFrom` return `true` on success and revert
  with the inherited ERC-6093 errors on failure.
- Zero-value transfers and self-transfers are supported. Transfers to the zero
  address and approvals to the zero address revert, including for zero amounts.
- Approvals replace the previous allowance. Finite allowances decrease with
  `transferFrom`; `type(uint256).max` represents an unlimited allowance and is
  not decreased. `approve` emits `Approval`; allowance spending does not emit
  `Approval` in this implementation. Every successful transfer emits `Transfer`.
- The deployer initially controls the whole balance, with the same transfer
  and approval rights as any holder. It has no lasting special authority.

## Reproducible local checks

Run these commands from the repository root with Foundry and Solidity 0.8.26
installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity `0.8.26`, the Cancun EVM target, and optimization at
200 runs. `bytecode_hash = "none"` and `cbor_metadata = false` exclude metadata
from the deployed bytecode. FFI and filesystem cheatcode permissions are not
enabled. No compiler executable is included in the repository.

All Solidity dependencies are ordinary files under `lib/`; no package download,
submodule, RPC endpoint, private key, environment variable, or fork is needed
to build or test. [`DEPENDENCIES.json`](DEPENDENCIES.json) records exact source
commits and archive checksums. The OpenZeppelin dependency contains only the
required ERC-20 source files and their license; forge-std contains its `src/`
tree and licenses. Vendored files are unmodified.

The tests cover:

- Exact metadata, constructor mint event, and full supply for arbitrary deployers.
- Transfers, approvals, revocation, finite/unlimited allowances, events, zero
  amounts, self-transfers, and full-balance transfers.
- Insufficient balances or allowances, invalid recipients/spenders, unauthorized
  spending, native-ETH rejection, and atomic rollback on failure.
- CREATE2 factory deployment without arguments, exact 10%/88%/2% distribution,
  subsequent claims, transfers in both directions with a pool custodian, and
  rejection of attempted minting, burning, and administrative calls.
- Deployed size and absence of external-call, delegatecall, callcode, and
  selfdestruct opcodes, skipping PUSH instruction data.
- Fuzz inputs (256 runs per fuzz test) and stateful invariant testing (128 runs
  of 64 operations) against an independent balance and allowance model.

Tests use isolated local actors and fresh deployments. They do not read or write
environment variables or rely on other tests' execution order. The launch
fixtures check token behavior, not actual Uniswap swaps, pool pricing, or
Merkle proofs. The network's supplied protected harness performs those broader
launch integration checks separately; its external launch contracts and manifest
inputs are not part of this repository.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `SwarmCore` |
| Foundry artifact identifier | `src/SwarmCore.sol:SwarmCore` |
| Intended chain | Ethereum, chain ID `1` |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Initial supply recipient | The immediate deploying address (`msg.sender`) |
| Initial supply, smallest units | `1000000000000000000000000000` |
| External contract dependencies | None |
| Linked libraries | None |
| Initialization calls | None |

For review without broadcasting, inspect the built artifact:

```sh
forge inspect src/SwarmCore.sol:SwarmCore abi
forge inspect src/SwarmCore.sol:SwarmCore bytecode
forge inspect src/SwarmCore.sol:SwarmCore deployedBytecode
```

Deploy the creation bytecode directly through the authorized launch factory.
The factory receives the full supply; neither the factory caller nor the
transaction origin receives it automatically. An EOA deployment would instead
mint the full supply to that EOA. There are no address arguments to fill in and
the constructor makes no external calls, so deployment also works on an empty
chain.

The launch service owns pool creation, pricing, and distribution. The supplied
policy assigns 10% to the swarm distributor, 88% to pool allocation, and the
remaining 2% to the supplied remainder recipient. Those operations occur after
the constructor and are not hard-coded into this token. The separate manifest
step supplies the launch economics and addresses; this deliverable does not
create `launch.json`, deploy contracts, or broadcast transactions.

## After launch

There are no token settings, administrative keys, upkeep tasks, or setters.
The launch operator is responsible for deploying the reviewed artifact,
verifying its source and compiler settings, confirming metadata and supply,
and checking the constructor's `Transfer(address(0), factory, 10^27)` event and
subsequent distribution receipts. The full factory balance exists immediately
after construction; it may already be distributed by the end of the launch
transaction.

Holders are responsible for recipient correctness and spender approvals.
Prefer exact allowances; revoke an existing allowance and wait for confirmation
before granting a replacement to reduce the standard ERC-20 approval race.
Unlimited allowances authorize the spender to move future holdings as well.
Tokens sent to the token contract, or another contract that cannot return them,
cannot be rescued. Native ETH transfers are rejected, and forced ETH cannot be
recovered through this contract.

## Review scope

The implementation was reviewed against the supplied security reference:
all supply changes are confined to the constructor, balance movement requires
the holder or an allowance, failed calls roll back atomically, and token
operations make no external calls. Oracle, randomness, signature, proxy,
liquidity-management, and vault concerns are outside this token's behavior.
OpenZeppelin's checked preconditions bound its internal unchecked arithmetic.

Local validation includes compilation, unit and fuzz tests, stateful invariant
tests, and formatting. Slither and Mythril were not run. The supplied full
protected launch harness was read but is not reproduced or claimed as passed
locally. Independent adversarial review and launch integration verification
remain release responsibilities; these local checks are not a security audit.
