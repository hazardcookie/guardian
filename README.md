# RLUSD Guardian

A minimal, upgradeable treasury contract for Ripple's RLUSD and USDC stablecoins. It allows Ripple to pre-fund RLUSD & USDC balances and grant a small set of institutional market-makers the right to swap the two stablecoins at par (1:1 USD value).

## Features

- **UUPS upgradeable** (proxy pattern, upgradable logic)
- **Ownable** (Fireblocks/multisig admin)
- **Whitelist**: Only approved market-makers can swap
- **Supply management**: Designated supply managers can fund or withdraw RLUSD/USDC reserves
- **SafeERC20**: Robust token transfers, reentrancy protection
- **Decimal-aware**: Handles RLUSD (18 decimals) ↔ USDC (6 decimals) precisely
- **Emergency rescue**: Owner can recover any ERC20 tokens sent to the contract

---

## Supply Management Feature

The RLUSDGuardian contract supports a **supply manager** role, in addition to the owner and whitelisted market-makers. Supply managers are trusted addresses (e.g., treasury operators or bots) that can:

- **Fund the contract's RLUSD or USDC reserves** (deposit tokens into the contract)
- **Withdraw RLUSD or USDC from the contract's reserves** (to any address)

This allows for flexible, secure management of the contract's liquidity without giving full admin rights.

### Managing Supply Managers

- Only the contract **owner** can add or remove supply managers.
- Supply managers are tracked in a mapping and can be queried.

#### Key Functions

- `addSupplyManager(address account)`: Owner-only. Grants supply manager role.
- `removeSupplyManager(address account)`: Owner-only. Revokes supply manager role.
- `isSupplyManager(address account)`: View. Checks if an address is a supply manager.
- `fundReserve(address token, uint256 amount)`: Supply manager or owner. Deposit RLUSD or USDC into the contract.
- `withdrawReserve(address token, uint256 amount, address to)`: Supply manager or owner. Withdraw RLUSD or USDC to any address.

See the contract and tests for full details and edge cases.

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
- **Supply manager role and reserve management**
- Swap logic (RLUSD ↔ USDC)
- Decimal conversion correctness
- Emergency rescue
- Upgradeability

### 5. Format the Code

```sh
forge fmt
```

### 6. Configure Environment Variables (.env)

Create a `.env` file in the project root and fill in the following keys (do **not** commit this file!):

```ini
# RPC endpoint for Sepolia (Alchemy, Infura, or a public endpoint)
SEPOLIA_RPC=https://ethereum-sepolia-rpc.publicnode.com

# Etherscan API key used for automatic contract verification
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY_HERE

# Private key of the deployer account that holds Sepolia ETH
DEPLOYER_KEY=0xYOUR_PRIVATE_KEY

# Address that will be set as the cold owner of the Guardian (no private key required) - This can be any address: eoa, gnosis safe, fireblocks etc
COLD_OWNER=0xYourColdOwnerAddress

# Pre-existing RLUSD & USDC ERC-20 token addresses on Sepolia
RLUSD_TOKEN=0x...
USDC_TOKEN=0x...
```

### 7. Deploy to Sepolia

The repository contains a Forge script that deploys an upgradeable `RLUSDGuardian` proxy and automatically verifies the implementation on Etherscan.

```sh
forge script script/DeployGuardian.s.sol \
  --rpc-url   $SEPOLIA_RPC \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --chain-id 11155111 \
  -vvvv       # verbose output
```

After the transaction is mined and the verification step completes Forge will print a link to the verified contract on Sepolia Etherscan.

---

## Contract Overview

**File:** `src/RLUSDGuardian.sol`

The RLUSDGuardian contract is a proxy-upgradeable treasury for RLUSD and USDC. Its main features:

- **Whitelisting:** Only approved market-makers can swap tokens.
- **Supply management:** Owner-designated supply managers can fund or withdraw RLUSD/USDC reserves.
- **Swaps:** Whitelisted addresses can swap RLUSD for USDC and vice versa at a 1:1 USD value, with correct decimal handling (18 ↔ 6).
- **Admin Controls:** Only the owner can add/remove whitelisted addresses or supply managers, upgrade the contract, or rescue tokens.
- **Security:** Uses OpenZeppelin's SafeERC20, Ownable, and ReentrancyGuard for robust, secure operations.
- **Upgradeability:** UUPS pattern allows the contract logic to be upgraded while preserving state.

### Key Functions

- `initialize(address rlusd, address usdc, address owner)`: Proxy initializer.
- `addWhitelist(address)`, `removeWhitelist(address)`: Owner-only, manage market-makers.
- `addSupplyManager(address)`, `removeSupplyManager(address)`: Owner-only, manage supply managers.
- `isSupplyManager(address)`: View, check supply manager status.
- `fundReserve(address, uint256)`, `withdrawReserve(address, uint256, address)`: Supply manager or owner, manage reserves.
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
