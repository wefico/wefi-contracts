// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title WFIDistributorTest
 * @notice Tests for the WFIDistributor contract using Foundry and forge-std/Test.sol.
 */

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/WFIDistributor.sol";

/**
 * @dev A simple ERC20 token for testing purposes.
 */
contract ERC20Mock is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        address initialAccount,
        uint256 initialBalance
    ) ERC20(name, symbol) {
        _mint(initialAccount, initialBalance);
    }
}

contract WFIDistributorTest is Test {
    // Contracts
    ERC20Mock public wfiToken;
    WFIDistributor public distributorContract;

    // Addresses
    address public owner = address(0xABCD);
    address public user = address(0x1234);
    address public treasury = address(0xDEAD);

    // Launch timestamp
    uint256 public launchTimestamp;

    // Constants
    uint256 public totalSupply = 1_000_000_000 * 1e18;

    function setUp() public {
        // Label addresses for readability in test output
        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(treasury, "Treasury");

        // Deploy a mock WFI token and mint total supply to the owner
        vm.startPrank(owner);
        wfiToken = new ERC20Mock("WeChain Token", "WFI", owner, totalSupply);
        vm.stopPrank();

        // Set the launch timestamp to the current block timestamp + 1 hour
        launchTimestamp = block.timestamp + 1 hours;

        // Deploy the WFIDistributor contract
        vm.startPrank(owner);
        distributorContract = new WFIDistributor(owner, IERC20(address(wfiToken)), launchTimestamp);
        vm.stopPrank();

        // Transfer tokens to the distribution contract
        vm.startPrank(owner);
        wfiToken.transfer(address(distributorContract), distributorContract.TOTAL_POOL_AMOUNT());
        vm.stopPrank();
    }

    /**
     * @notice Test initialization and basic setup.
     */
    function testInitialization() public view {
        // Check initial state variables
        assertEq(distributorContract.launchTimestamp(), launchTimestamp);
        assertEq(distributorContract.lastMiningUpdate(), launchTimestamp);
        assertEq(distributorContract.lastReferralUpdate(), launchTimestamp);

        // Check the WFI token balance of the distribution contract
        uint256 contractBalance = wfiToken.balanceOf(address(distributorContract));
        assertEq(contractBalance, distributorContract.TOTAL_POOL_AMOUNT());
    }

    /**
     * @notice Test claiming mining rewards before the launch timestamp.
     */
    function testCannotClaimMiningRewardsBeforeLaunch() public {
        vm.startPrank(user);
        vm.expectRevert("Distribution has not started yet");
        distributorContract.claimMiningRewards();
        vm.stopPrank();
    }

    /**
     * @notice Test claiming referral rewards before the launch timestamp.
     */
    function testCannotClaimReferralRewardsBeforeLaunch() public {
        vm.startPrank(user);
        vm.expectRevert("Distribution has not started yet");
        distributorContract.claimReferralRewards();
        vm.stopPrank();
    }

    /**
     * @notice Test claiming mining rewards after launch.
     */
    function testClaimMiningRewards() public {
        // Warp to just after launch timestamp
        vm.warp(launchTimestamp + 1);

        vm.startPrank(user);
        distributorContract.claimMiningRewards();
        vm.stopPrank();

        // Calculate expected rewards
        uint256 elapsedTime = block.timestamp - launchTimestamp;
        uint256 expectedReward = elapsedTime * 8 * 1e18; // First interval emission rate

        // Check user's WFI token balance
        uint256 userBalance = wfiToken.balanceOf(user);
        assertEq(userBalance, expectedReward);

        // Check totalMiningDistributed
        uint256 totalDistributed = distributorContract.totalMiningDistributed();
        assertEq(totalDistributed, expectedReward);
    }

    /**
     * @notice Test claiming referral rewards after launch.
     */
    function testClaimReferralRewards() public {
        // Warp to just after launch timestamp
        vm.warp(launchTimestamp + 1);

        vm.startPrank(user);
        distributorContract.claimReferralRewards();
        vm.stopPrank();

        // Calculate expected rewards
        uint256 elapsedTime = block.timestamp - launchTimestamp;
        uint256 totalVested = (distributorContract.REFERRAL_STAKING_POOL() * elapsedTime) /
            (730 days);
        uint256 expectedReward = totalVested;

        // Check user's WFI token balance
        uint256 userBalance = wfiToken.balanceOf(user);
        assertEq(userBalance, expectedReward);

        // Check totalReferralDistributed
        uint256 totalDistributed = distributorContract.totalReferralDistributed();
        assertEq(totalDistributed, expectedReward);
    }

    /**
     * @notice Test pausing and unpausing the contract.
     */
    function testPauseAndUnpause() public {
        // Warp to after launch
        vm.warp(launchTimestamp + 1);

        // Pause the contract
        vm.startPrank(owner);
        distributorContract.pause();
        vm.stopPrank();

        // Attempt to claim rewards while paused
        vm.startPrank(user);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        distributorContract.claimMiningRewards();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        distributorContract.claimReferralRewards();
        vm.stopPrank();

        // Unpause the contract
        vm.startPrank(owner);
        distributorContract.unpause();
        vm.stopPrank();

        // Claim rewards after unpausing
        vm.startPrank(user);
        distributorContract.claimMiningRewards();
        distributorContract.claimReferralRewards();
        vm.stopPrank();

        // Check balances to ensure rewards were received
        uint256 userBalance = wfiToken.balanceOf(user);
        assertTrue(userBalance > 0);
    }

    /**
     * @notice Test transferring remaining tokens after distribution period.
     */
    function testTransferRemainingTokens() public {
        // Warp to after distribution periods
        uint256 miningDuration = distributorContract.miningRewardsDuration();
        uint256 referralDuration = distributorContract.REFERRAL_VESTING_DURATION();
        uint256 maxDuration = miningDuration > referralDuration ? miningDuration : referralDuration;

        vm.warp(launchTimestamp + maxDuration + 1);

        // Attempt to transfer remaining tokens
        vm.startPrank(owner);
        distributorContract.transferRemainingTokens(treasury);
        vm.stopPrank();

        // Check treasury balance
        uint256 treasuryBalance = wfiToken.balanceOf(treasury);
        assertTrue(treasuryBalance > 0);

        // Ensure all tokens have been transferred
        uint256 contractBalance = wfiToken.balanceOf(address(distributorContract));
        assertEq(contractBalance, 0);
    }

    /**
     * @notice Test that non-owner cannot pause the contract.
     */
    function testNonOwnerCannotPause() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        distributorContract.pause();
        vm.stopPrank();
    }

    /**
     * @notice Test that non-owner cannot transfer remaining tokens.
     */
    function testNonOwnerCannotTransferRemainingTokens() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        distributorContract.transferRemainingTokens(treasury);
        vm.stopPrank();
    }

    /**
     * @notice Test claiming mining rewards over multiple intervals.
     */
    function testClaimMiningRewardsMultipleIntervals() public {
        // Warp to after the first interval
        uint256 firstIntervalDuration = distributorContract.intervalDurations(0);
        vm.warp(launchTimestamp + firstIntervalDuration + 1);

        vm.startPrank(user);
        distributorContract.claimMiningRewards();
        vm.stopPrank();

        // Calculate expected rewards
        uint256 expectedReward = firstIntervalDuration * 8 * 1e18;

        // Add rewards from the second interval
        uint256 elapsedTime = block.timestamp - (launchTimestamp + firstIntervalDuration);
        uint256 secondIntervalElapsed = elapsedTime;
        expectedReward += secondIntervalElapsed * 4 * 1e18;

        // Check user's WFI token balance
        uint256 userBalance = wfiToken.balanceOf(user);
        assertEq(userBalance, expectedReward);
    }

    /**
     * @notice Test that claiming rewards cannot exceed the allocated pools.
     */
    function testCannotExceedAllocatedPools() public {
        // Warp to after the entire mining duration
        uint256 miningDuration = distributorContract.miningRewardsDuration();
        vm.warp(launchTimestamp + miningDuration + 1);

        vm.startPrank(user);
        distributorContract.claimMiningRewards();
        vm.stopPrank();

        // Attempt to claim again should result in zero reward
        vm.startPrank(user);
        vm.expectRevert("No mining rewards to claim");
        distributorContract.claimMiningRewards();
        vm.stopPrank();

        // Total distributed should not exceed MINING_REWARDS_POOL
        uint256 totalDistributed = distributorContract.totalMiningDistributed();
        assertEq(totalDistributed, distributorContract.MINING_REWARDS_POOL());
    }
}
