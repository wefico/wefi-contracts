// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title WFI Token Distribution Contract
 * @notice This contract manages the distribution of WFI tokens for the WeChain project on Binance Smart Chain.
 * It handles mining rewards with a halving schedule and referral/staking rewards with linear vesting over 2 years.
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract WFIDistributor is Ownable, Pausable, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // WFI token interface
    IERC20 public immutable wfiToken;
    address public verifierAddress;

    // Launch timestamp from which all time-based calculations begin
    uint256 public immutable launchTimestamp;

    // Constants defining the total tokens allocated to each pool
    uint256 public constant MINING_REWARDS_POOL = 862_068_966 * 1e18; // Adjust decimals if WFI token has different decimals
    uint256 public constant REFERRAL_STAKING_POOL = 137_931_034 * 1e18;
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

    // Struct to store claim data per user
    struct ClaimData {
        address claimedFrom;
        uint256 timestamp;
        uint256 validUntil;
        uint256 amount;
    }

    // Mapping to store claim data per user
    mapping(bytes => ClaimData) public claims;
    // Mapping to store claim data signatures per user for mining rewards
    mapping(address => bytes[]) public miningClaims;
    // Mapping to store claim data signatures per user for referral rewards
    mapping(address => bytes[]) public referralClaims;

    // Events for monitoring
    event MiningRewardsClaimed(address indexed user, uint256 amount);
    event ReferralRewardsClaimed(address indexed user, uint256 amount);
    event RemainingTokensTransferred(address indexed to, uint256 amount);

    /**
     * @dev Constructor sets the WFI token address and launch timestamp.
     * @param _wfiToken Address of the WFI token contract.
     * @param _launchTimestamp The timestamp from which distributions start.
     */
    constructor(address _newOwner, IERC20 _wfiToken, uint256 _launchTimestamp, address _verifierAddress) Ownable(_newOwner) {
        require(address(_wfiToken) != address(0), "Invalid token address");
        require(_launchTimestamp >= block.timestamp, "Launch timestamp must be in the future");

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
     * @param signature The bytes signature associated with the claim.
     */
    function claimMiningRewards(uint256 amount, uint256 validUntil, bytes memory signature) external whenNotPaused nonReentrant {
        // Verify the signature
        require(claims[signature].amount == 0, "Claim already exists");
        require(validUntil >= block.timestamp, "Claim expired");
        require(wfiToken.balanceOf(address(this)) >= amount, "Not enough WFI available on the contract");
        // Verify if provided arguments and signature are valid and matching
        bytes32 messageHash = keccak256(
            // Sequence of arguments is important here
            abi.encodePacked(msg.sender, amount, validUntil)
        ).toEthSignedMessageHash();
        address signer = messageHash.recover(signature);
        require(signer == verifierAddress, "Invalid signature");

        require(block.timestamp > launchTimestamp, "Distribution has not started yet");

        uint256 claimable = totalUnlockedMiningRewards();
        require(claimable > 0, "No mining rewards to claim");
        require(claimable - totalMiningDistributed >= amount, "Amount exceeds claimable rewards");
        require(totalMiningDistributed + amount <= MINING_REWARDS_POOL, "Exceeds mining rewards pool");

        totalMiningDistributed += amount;
        // Store claim data
        claims[signature] = ClaimData({claimedFrom: msg.sender, timestamp: block.timestamp, validUntil: validUntil, amount: amount});
        miningClaims[msg.sender].push(signature);

        // Transfer the calculated reward to the caller
        wfiToken.transfer(msg.sender, amount);

        emit MiningRewardsClaimed(msg.sender, amount);
    }

    /**
     * @notice Calculates the claimable mining rewards based on the time elapsed and emission rates.
     * @return totalReward The total mining rewards claimable by the caller.
     */
    function totalUnlockedMiningRewards() public view returns (uint256) {
        uint256 totalReward = 0;
        uint256 timeElapsed = block.timestamp > launchTimestamp ? block.timestamp - launchTimestamp : 0;
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
     * @param signature The bytes signature associated with the claim.
     */
    function claimReferralRewards(uint256 amount, uint256 validUntil, bytes memory signature) external whenNotPaused nonReentrant {
        // Verify the signature
        require(claims[signature].amount == 0, "Claim already exists");
        require(validUntil >= block.timestamp, "Claim expired");
        require(wfiToken.balanceOf(address(this)) >= amount, "Not enough WFI available on the contract");
        // Verify if provided arguments and signature are valid and matching
        bytes32 messageHash = keccak256(
            // Sequence of arguments is important here
            abi.encodePacked(msg.sender, amount, validUntil)
        ).toEthSignedMessageHash();
        address signer = messageHash.recover(signature);
        require(signer == verifierAddress, "Invalid signature");

        require(block.timestamp > launchTimestamp, "Distribution has not started yet");

        uint256 claimable = totalUnlockedReferralRewards();
        require(claimable > 0, "No referral rewards to claim");
        require(claimable - totalReferralDistributed >= amount, "Amount exceeds claimable rewards");
        require(totalReferralDistributed + amount <= REFERRAL_STAKING_POOL, "Exceeds referral/staking rewards pool");

        totalReferralDistributed += amount;
        // Store claim data
        claims[signature] = ClaimData({claimedFrom: msg.sender, timestamp: block.timestamp, validUntil: validUntil, amount: amount});
        referralClaims[msg.sender].push(signature);

        // Transfer the calculated reward to the caller
        wfiToken.transfer(msg.sender, amount);

        emit ReferralRewardsClaimed(msg.sender, amount);
    }

    /**
     * @notice Calculates the claimable referral and staking rewards based on linear vesting.
     * @return claimable The total referral and staking rewards claimable by the caller.
     */
    function totalUnlockedReferralRewards() public view returns (uint256) {
        uint256 elapsedTime = block.timestamp > launchTimestamp ? block.timestamp - launchTimestamp : 0;
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
     * @notice Transfers any remaining tokens to a specified address after the distribution period.
     * @param to The address to receive the remaining tokens.
     */
    function transferRemainingTokens(address to) external onlyOwner {
        require(to != address(0), "Invalid address");
        require(_isDistributionPeriodOver(), "Distribution period is not over yet");

        uint256 remainingMiningTokens = MINING_REWARDS_POOL > totalMiningDistributed ? MINING_REWARDS_POOL - totalMiningDistributed : 0;
        uint256 remainingReferralTokens = REFERRAL_STAKING_POOL > totalReferralDistributed
            ? REFERRAL_STAKING_POOL - totalReferralDistributed
            : 0;

        uint256 totalRemainingTokens = remainingMiningTokens + remainingReferralTokens;
        require(totalRemainingTokens > 0, "No remaining tokens to transfer");

        wfiToken.transfer(to, totalRemainingTokens);

        emit RemainingTokensTransferred(to, totalRemainingTokens);
    }

    /**
     * @notice Checks if the distribution periods are over for both mining and referral rewards.
     * @return True if both distribution periods are over, otherwise false.
     */
    function _isDistributionPeriodOver() internal view returns (bool) {
        bool miningOver = block.timestamp >= launchTimestamp + miningRewardsDuration;
        bool referralOver = block.timestamp >= launchTimestamp + REFERRAL_VESTING_DURATION;
        return miningOver && referralOver;
    }
}
