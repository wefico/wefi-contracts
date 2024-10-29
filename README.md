# WFI Token Distribution Contract

## Overview

This repository contains the **WFI Token Distribution Contract** for the **WeChain** project on Binance Smart Chain (BSC). The contract manages the distribution of WFI tokens, ensuring transparency, security, and long-term sustainability. It handles mining rewards with a halving schedule and referral/staking rewards with linear vesting over 2 years.

## Features

- **Mining Rewards Pool**: Distributes mining rewards totaling 862,068,966 WFI tokens with a halving schedule over four intervals.
- **Referral and Staking Pool**: Manages 137,931,034 WFI tokens with linear vesting over 2 years.
- **Halving Schedule**:
  - **1st Interval**: 8 WFI per block for 57,471,264 blocks.
  - **2nd Interval**: 4 WFI per block for 57,471,264 blocks.
  - **3rd Interval**: 2 WFI per block for 57,471,264 blocks.
  - **4th Interval**: 1 WFI per block for 57,471,270 blocks.
- **Blockchain Migration Support**: Includes mechanisms to handle token distribution during migration to WeChain blockchain.
- **Security**: Implements protections against common smart contract vulnerabilities.

## Technical Specifications

- **Solidity Version**: ^0.8.20
- **Framework**: [Foundry](https://book.getfoundry.sh/)
- **Libraries**:
  - [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
- **Continuous Integration**: [GitHub Actions](https://github.com/features/actions)

## Prerequisites

- **Foundry**: Install via the [Foundry installation guide](https://book.getfoundry.sh/getting-started/installation).
- **Bun**: For managing dependencies and scripts via [Bun](https://bun.sh/docs/installation).

## Installation

1. **Clone the repository**:

   ```bash
   git clone https://github.com/yourusername/wechain-wfi-distribution.git
   cd wechain-wfi-distribution
   ```

2. **Install Dependencies**:

   - Install OpenZeppelin & Foundry/Forge dependencies:

     ```bash
     forge install
     ```

## Usage

The main contract is located at `src/WFIDistributor.sol`.

### Deployment

To deploy the contract, you will need:

- The WFI token contract address on BSC.
- The launch timestamp (must be in the future).
- The verifier address (used for signature verification).
- The owner address (who will have administrative control over the contract).

### Key Functions

- `claimMiningRewards(uint256 amount, uint256 validUntil, bytes memory signature)`: Allows users to claim mining rewards.
- `claimReferralRewards(uint256 amount, uint256 validUntil, bytes memory signature)`: Allows users to claim referral and staking rewards.
- `totalUnlockedMiningRewards()`: Returns the total mining rewards unlocked to date.
- `totalUnlockedReferralRewards()`: Returns the total referral and staking rewards unlocked to date.
- `pause()` and `unpause()`: Admin functions to pause or unpause reward claiming.
- `setBlockchainMigrationTimestamp(uint256 timestamp)`: Sets the timestamp for blockchain migration.
- `transferRemainingTokens(address to)`: Transfers remaining tokens after migration period.

## Testing

We use **Foundry** for testing the smart contract.

### Running Tests

1. **Compile Contracts**:

   ```bash
   forge build
   ```

2. **Run Tests**:

   ```bash
   forge test
   ```

   This will execute all the tests in the `test/` directory.

## Security Considerations

We have implemented several security measures as per the project documentation:

- **Reentrancy Protection**: Using `ReentrancyGuard` from OpenZeppelin.
- **Access Control**: Using `Ownable` for admin functions.
- **Signature Verification**: Using ECDSA signature verification for claims.
- **Integer Overflow/Underflow Protection**: Solidity 0.8.x has built-in overflow checks.
- **Pausable Contract**: Allows the owner to pause reward claiming in case of emergencies.
- **Blockchain Migration Safety**: Mechanisms to safely migrate to WeChain blockchain.

### Known Limitations

- The contract relies on off-chain signatures for verifying claims (`verifierAddress`). Ensure that the verifier's private key is securely managed.
- The contract has blockchainMigrationTimestamp and blockchainMigrationLockTimestamp to handle migration to Wechain blockchain. It will be used in the future to migrate the contract to Wechain and transfer the remaining tokens to the treasury.

## Continuous Integration

We use **GitHub Actions** for continuous integration. The CI workflow is defined in `.github/workflows/contracts.yml`.

### CI Workflow Includes:

- **Automatic Testing**: Runs `forge test` on every push and pull request.
- **Linting and Formatting**: Checks code style and formatting.
