# RLUSD Guardian

A minimal, upgradeable treasury contract for Ripple's RLUSD and USDC stablecoins. It allows Ripple to pre-fund RLUSD & USDC balances and grant a small set of institutional market-makers the right to swap the two stablecoins at par (1:1 USD value).

## Features

- **UUPS upgradeable** (proxy pattern, upgradable logic)
- **Ownable** (Fireblocks/multisig admin)
- **Whitelist**: Only approved market-makers can swap
- **SafeERC20**: Robust token transfers, reentrancy protection
- **Decimal-aware**: Handles RLUSD (18 decimals) ↔ USDC (6 decimals) precisely
- **Emergency rescue**: Owner can recover any ERC20 tokens sent to the contract

---

## Quickstart

### 1. Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (for `forge`, `anvil`, etc.)
- `git` (for cloning and submodules)
- [Node.js](https://nodejs.org/) (optional, for some scripts, not required for core contract/test usage)

### 2. Clone and Install Dependencies

```sh
git clone <this-repo-url>
cd <this-repo-directory>
git submodule update --init --recursive
```

Install OpenZeppelin contracts:

```sh
forge install openzeppelin/openzeppelin-contracts@v5.1.0 
```

Install OpenZeppelin contracts upgradeable:

```sh
forge install openzeppelin/openzeppelin-contracts-upgradeable@v5.1.0
```

This will pull in dependencies like OpenZeppelin and forge-std into `lib/`.

### 3. Build the Contracts

```sh
forge build
```

### 4. Run the Tests

```sh
forge test
```

All tests are in `test/RLUSDGuardian.t.sol` and cover:
- Whitelist management
- Swap logic (RLUSD ↔ USDC)
- Decimal conversion correctness
- Emergency rescue
- Upgradeability

### 5. Format the Code

```sh
forge fmt
```

### 6. Local Node (optional, for scripting)

```sh
anvil
```

---

## Contract Overview

**File:** `src/RLUSDGuardian.sol`

The RLUSDGuardian contract is a proxy-upgradeable treasury for RLUSD and USDC. Its main features:

- **Whitelisting:** Only approved market-makers can swap tokens.
- **Swaps:** Whitelisted addresses can swap RLUSD for USDC and vice versa at a 1:1 USD value, with correct decimal handling (18 ↔ 6).
- **Admin Controls:** Only the owner can add/remove whitelisted addresses, upgrade the contract, or rescue tokens.
- **Security:** Uses OpenZeppelin's SafeERC20, Ownable, and ReentrancyGuard for robust, secure operations.
- **Upgradeability:** UUPS pattern allows the contract logic to be upgraded while preserving state.

### Key Functions

- `initialize(address rlusd, address usdc, address owner)`: Proxy initializer.
- `addWhitelist(address)`, `removeWhitelist(address)`: Owner-only, manage market-makers.
- `swapRLUSDForUSDC(uint256)`, `swapUSDCForRLUSD(uint256)`: Whitelisted only, atomic swaps.
- `rescueTokens(address token, uint256 amount, address to)`: Owner-only, recover tokens.
- `upgradeToAndCall(address newImplementation, bytes data)`: Owner-only, upgrade logic.

---

## Directory Structure

- `src/` – Main contract(s)
- `test/` – Foundry tests
- `lib/` – External dependencies (OpenZeppelin, forge-std, etc.)
- `foundry.toml` – Project config (Solidity version, remappings, etc.)

---

## Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
- [OpenZeppelin Contracts Upgradeable](https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable)
- [forge-std](https://github.com/foundry-rs/forge-std)

---

**To deploy or interact with the contract, write a script in the `script/` directory and use `forge script`. See the [Foundry Book](https://book.getfoundry.sh/) for more.**
