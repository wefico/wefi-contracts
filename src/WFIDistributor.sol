// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/**
 * @title WFI Token Distribution Contract
 * @notice This contract manages the distribution of WFI tokens for the WeChain project on Binance Smart Chain.
 * It handles mining rewards with a halving schedule and referral/staking rewards with linear vesting over 2 years.
 */

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract WFIDistributor is Ownable2Step, Pausable, ReentrancyGuard, EIP712 {
    using ECDSA for bytes32;

    // Custom Errors
    error InvalidTokenAddress(address tokenAddress);
    error InvalidVerifierAddress(address verifierAddress);
    error ClaimAlreadyExists();
    error ClaimExpired();
    error InsufficientContractBalance();
    error InvalidSignature();
    error DistributionNotStarted();
    error NoMiningRewards();
    error ExceedsClaimableRewards();
    error ExceedsMiningRewardsPool();
    error NoReferralRewards();
    error ExceedsClaimableReferralRewards();
    error ExceedsReferralStakingPool();
    error IncorrectMigrationTimestamp();
    error MigrationTimestampAlreadySet();
    error InvalidAddress();
    error MigrationNotSet();
    error MigrationNotCompleted();
    error NoRemainingTokens();

    // WFI token interface
    IERC20 public immutable wfiToken;
    address public immutable verifierAddress;

    // Launch timestamp from which all time-based calculations begin
    uint256 public immutable launchTimestamp;

    // Constants defining the total tokens allocated to each pool
    uint256 public constant MINING_REWARDS_POOL = 862_068_966 * 1e18;
    uint256 public constant REFERRAL_STAKING_POOL = 127_931_034 * 1e18;
    uint256 public constant TOTAL_POOL_AMOUNT = MINING_REWARDS_POOL + REFERRAL_STAKING_POOL;

    // Emission rates for mining rewards per interval (tokens per second)
    uint256[] public tokensPerSecond = [8 * 1e18, 4 * 1e18, 2 * 1e18, 1 * 1e18];

    // Duration of each mining interval in seconds
    uint256[] public intervalDurations = [
        57_471_264, // First interval
        57_471_264, // Second interval
        57_471_264, // Third interval
        57_471_270 // Fourth interval
    ];

    // Total duration for mining rewards
    uint256 public miningRewardsDuration;

    // Referral and staking vesting duration (2 years)
    uint256 public constant REFERRAL_VESTING_DURATION = 730 days;

    // Tracking variables for mining rewards
    uint256 public totalMiningDistributed;
    // Tracking variable for referral and staking rewards
    uint256 public totalReferralDistributed;

    // Variable for migration to Wechain blockchain
    uint256 public blockchainMigrationLockTimestamp;
    uint256 public blockchainMigrationTimestamp;

    // Struct to store claim data per user
    struct ClaimData {
        address receiver;
        uint256 amount;
    }

    // Mapping to store claim data per user
    mapping(bytes => ClaimData) public claims;
    // Mapping to track whether a signature has already been used to prevent replay attacks
    mapping(bytes => bool) public isSignatureUsed;

    // Events for monitoring
    event MiningRewardsClaimed(address indexed user, uint256 amount);
    event ReferralRewardsClaimed(address indexed user, uint256 amount);
    event RemainingTokensTransferred(address indexed to, uint256 amount);
    event BlockchainMigrationStarted(uint256 timestamp);

    // EIP-712 TypeHash
    bytes32 private constant CLAIM_TYPEHASH = keccak256("Claim(address receiver,uint256 amount,uint256 validUntil,bool isMiningClaim)");

    /**
     * @dev Constructor sets the WFI token address and launch timestamp.
     * @param _wfiToken Address of the WFI token contract.
     * @param _launchTimestamp The timestamp from which distributions start.
     */
    constructor(
        address _newOwner,
        IERC20 _wfiToken,
        uint256 _launchTimestamp,
        address _verifierAddress
    ) Ownable(_newOwner) EIP712("WFIDistributor", "1") {
        if (address(_wfiToken) == address(0)) {
            revert InvalidTokenAddress(address(_wfiToken));
        }
        if (address(_verifierAddress) == address(0)) {
            revert InvalidVerifierAddress(address(_verifierAddress));
        }

        verifierAddress = _verifierAddress;
        wfiToken = _wfiToken;
        launchTimestamp = _launchTimestamp;

        // Calculate total mining rewards duration
        for (uint256 i = 0; i < intervalDurations.length; i++) {
            miningRewardsDuration += intervalDurations[i];
        }
    }

    /**
     * @notice Claims the accumulated mining rewards for the caller.
     * @param amount The amount of WFI to claim.
     * @param validUntil The timestamp until which the claim is valid.
     * @param receiverAddress The address of the receiver of the rewards.
     * @param signature The bytes signature associated with the claim.
     */
    function claimMiningRewards(
        uint256 amount,
        uint256 validUntil,
        address receiverAddress,
        bytes memory signature
    ) external whenNotPaused nonReentrant {
        // Verify the signature
        if (isSignatureUsed[signature]) {
            revert ClaimAlreadyExists();
        }
        if (validUntil < block.timestamp) {
            revert ClaimExpired();
        }
        if (wfiToken.balanceOf(address(this)) < amount) {
            revert InsufficientContractBalance();
        }
        // Verify if provided arguments and signature are valid and matching
        if (!_verifyClaim(receiverAddress, amount, validUntil, true, signature)) {
            revert InvalidSignature();
        }

        if (block.timestamp <= launchTimestamp) {
            revert DistributionNotStarted();
        }

        uint256 claimable = totalUnlockedMiningRewards();
        if (claimable <= 0) {
            revert NoMiningRewards();
        }
        if (claimable - totalMiningDistributed < amount) {
            revert ExceedsClaimableRewards();
        }
        if (totalMiningDistributed + amount > MINING_REWARDS_POOL) {
            revert ExceedsMiningRewardsPool();
        }

        totalMiningDistributed += amount;
        // Store claim data
        isSignatureUsed[signature] = true;
        claims[signature] = ClaimData({receiver: receiverAddress, amount: amount});

        // Transfer the calculated reward to the caller
        wfiToken.transfer(receiverAddress, amount);

        emit MiningRewardsClaimed(receiverAddress, amount);
    }

    /**
     * @notice Calculates the claimable mining rewards based on the time elapsed and emission rates.
     * @return totalReward The total mining rewards claimable by the caller.
     */
    function totalUnlockedMiningRewards() public view returns (uint256) {
        uint256 totalReward = 0;
        // If blockchainMigrationTimestamp is set, total unlocked will be only until this timestamp
        uint256 currentTimestamp = blockchainMigrationTimestamp != 0 ? blockchainMigrationLockTimestamp : block.timestamp;
        uint256 timeElapsed = currentTimestamp > launchTimestamp ? currentTimestamp - launchTimestamp : 0;
        uint256 timeLeft = timeElapsed;
        for (uint256 i = 0; i < intervalDurations.length; i++) {
            uint256 intervalTime = intervalDurations[i];
            uint256 rewardRate = tokensPerSecond[i];
            if (timeLeft >= intervalTime) {
                totalReward += rewardRate * intervalTime;
                timeLeft -= intervalTime;
            } else {
                totalReward += rewardRate * timeLeft;
                break; // No more time left to account for
            }
        }
        return totalReward;
    }

    /**
     * @notice Claims the accumulated referral and staking rewards for the caller.
     * @param amount The amount of WFI to claim.
     * @param validUntil The timestamp until which the claim is valid.
     * @param receiverAddress The address of the receiver of the rewards.
     * @param signature The bytes signature associated with the claim.
     */
    function claimReferralRewards(
        uint256 amount,
        uint256 validUntil,
        address receiverAddress,
        bytes memory signature
    ) external whenNotPaused nonReentrant {
        // Verify the signature
        if (isSignatureUsed[signature]) {
            revert ClaimAlreadyExists();
        }
        if (validUntil < block.timestamp) {
            revert ClaimExpired();
        }
        if (wfiToken.balanceOf(address(this)) < amount) {
            revert InsufficientContractBalance();
        }
        // Verify if provided arguments and signature are valid and matching
        if (!_verifyClaim(receiverAddress, amount, validUntil, false, signature)) {
            revert InvalidSignature();
        }

        if (block.timestamp <= launchTimestamp) {
            revert DistributionNotStarted();
        }

        uint256 claimable = totalUnlockedReferralRewards();
        if (claimable <= 0) {
            revert NoReferralRewards();
        }
        if (claimable - totalReferralDistributed < amount) {
            revert ExceedsClaimableReferralRewards();
        }
        if (totalReferralDistributed + amount > REFERRAL_STAKING_POOL) {
            revert ExceedsReferralStakingPool();
        }

        totalReferralDistributed += amount;
        // Store claim data
        isSignatureUsed[signature] = true;
        claims[signature] = ClaimData({receiver: receiverAddress, amount: amount});

        // Transfer the calculated reward to the caller
        wfiToken.transfer(receiverAddress, amount);

        emit ReferralRewardsClaimed(receiverAddress, amount);
    }

    /**
     * @notice Calculates the claimable referral and staking rewards based on linear vesting.
     * @return claimable The total referral and staking rewards claimable by the caller.
     */
    function totalUnlockedReferralRewards() public view returns (uint256) {
        // If blockchainMigrationTimestamp is set, total unlocked will be only until this timestamp
        uint256 currentTimestamp = blockchainMigrationTimestamp != 0 ? blockchainMigrationLockTimestamp : block.timestamp;
        uint256 elapsedTime = currentTimestamp > launchTimestamp ? currentTimestamp - launchTimestamp : 0;
        if (elapsedTime > REFERRAL_VESTING_DURATION) {
            elapsedTime = REFERRAL_VESTING_DURATION;
        }
        uint256 totalVestedAmount = (REFERRAL_STAKING_POOL * elapsedTime) / REFERRAL_VESTING_DURATION;
        return totalVestedAmount;
    }

    /**
     * @notice Allows the admin to pause the reward claiming functions.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Allows the admin to unpause the reward claiming functions.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Sets the timestamp for the blockchain migration.
     * @param timestamp The timestamp for the blockchain migration.
     */
    function setBlockchainMigrationTimestamp(uint256 timestamp) external onlyOwner {
        if (timestamp < block.timestamp + 7 days) {
            revert IncorrectMigrationTimestamp();
        }
        if (blockchainMigrationTimestamp != 0) {
            revert MigrationTimestampAlreadySet();
        }

        blockchainMigrationLockTimestamp = block.timestamp;
        blockchainMigrationTimestamp = timestamp;

        emit BlockchainMigrationStarted(timestamp);
    }

    /**
     * @notice Transfers any remaining tokens to a specified address at the blockchain migration period.
     * @param to The address to receive the remaining tokens.
     */
    function transferRemainingTokens(address to) external onlyOwner {
        if (to == address(0)) {
            revert InvalidAddress();
        }
        if (blockchainMigrationTimestamp == 0) {
            revert MigrationNotSet();
        }
        if (block.timestamp <= blockchainMigrationTimestamp) {
            revert MigrationNotCompleted();
        }

        uint256 remainingMiningTokens = totalUnlockedMiningRewards() - totalMiningDistributed;
        uint256 remainingReferralTokens = totalUnlockedReferralRewards() - totalReferralDistributed;

        uint256 totalRemainingTokens = remainingMiningTokens + remainingReferralTokens;
        if (totalRemainingTokens <= 0) {
            revert NoRemainingTokens();
        }

        // Update the distributed totals to prevent multiple withdrawals
        totalMiningDistributed += remainingMiningTokens;
        totalReferralDistributed += remainingReferralTokens;

        wfiToken.transfer(to, totalRemainingTokens);

        emit RemainingTokensTransferred(to, totalRemainingTokens);
    }

    function _verifyClaim(
        address receiver,
        uint256 amount,
        uint256 validUntil,
        bool isMiningClaim,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(CLAIM_TYPEHASH, receiver, amount, validUntil, isMiningClaim));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);
        return signer == verifierAddress;
    }
}
