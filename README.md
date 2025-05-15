# BatchCallAndSponsor - Sepolia Edition

An educational project demonstrating account abstraction and sponsored transaction execution using EIP-7702 on the Sepolia testnet. This project uses Foundry for deployment, scripting, and testing.

## Overview

The `BatchCallAndSponsor` contract enables batch execution of calls by verifying signatures over a nonce and batched call data. It supports:
- **Direct execution**: by the smart account itself.
- **Sponsored execution**: via an off-chain signature (by a sponsor).

Replay protection is provided by an internal nonce that increments after each batch execution.

## Features

- Batch transaction execution
- Off-chain signature verification using ECDSA
- Replay protection through nonce incrementation
- Support for both ETH and ERC-20 token transfers

## Prerequisites

- [Foundry](https://github.com/foundry-rs/foundry)
- Solidity ^0.8.20

## Running the Project on Sepolia

### Step 1: Install Foundry

```sh
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Step 2: Configure Environment Variables

Create or modify the `.env` file with your Sepolia RPC URL and private keys:

```
SEPOLIA_RPC=https://ethereum-sepolia-rpc.publicnode.com
EOA_PK=your_eoa_private_key_here
SPONSOR_PK=your_sponsor_private_key_here
```

### Step 3: Install Dependencies and Build

```sh
# Install dependencies
make update

# Build the contracts
make build
```

### Step 4: Run Tests on Sepolia

Tests have been updated to work with Sepolia and check for balance changes instead of absolute balances:

```bash
make test
```

Expected output:

```
[PASS] testDirectExecution() (gas: 121436)
Logs:
  EOA Address: 0xfA86ED07480F465eB2EbF6E970e12371EB87526B
  Sponsor Address: 0x0137882ef90C077ef9D48Dde2bC97C64EB8E4f98
  Sending 1 ETH from EOA to Sponsor and transferring 100 tokens to Sponsor in a single transaction
  Initial EOA balance: 10000000000000000000
  Initial Sponsor balance: 8725891919433764884

[PASS] testReplayAttack() (gas: 118403)

[PASS] testSponsoredExecution() (gas: 91828)

[PASS] testWrongSignature() (gas: 44206)
```

### Step 5: Deploy and Run Transactions on Sepolia

Deploy the contract and execute transactions on Sepolia:

```bash
make deploy
```

This command will:
1. Deploy the `BatchCallAndSponsor` contract to Sepolia
2. Deploy a `MockERC20` token contract
3. Mint tokens to your EOA
4. Execute a batch transaction directly from your EOA
5. Execute a sponsored transaction where the Sponsor pays for gas

All transactions will be executed on the Sepolia testnet and can be verified on a block explorer.