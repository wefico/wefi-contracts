// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title WFIDistributorTest
 * @notice Tests for the WFIDistributor contract using Foundry and forge-std/Test.sol.
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/WFIDistributor.sol";

/**
 * @dev A simple ERC20 token for testing purposes.
 */
contract ERC20Mock is ERC20 {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    constructor(string memory name, string memory symbol, address initialAccount, uint256 initialBalance) ERC20(name, symbol) {
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
    address public verifier;
    uint256 privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;

    // Launch timestamp
    uint256 public launchTimestamp;

    // Constants
    uint256 public totalSupply = 1_000_000_000 * 1e18;

    function setUp() public {
        // Label addresses for readability in test output
        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(treasury, "Treasury");
        verifier = vm.addr(privateKey);
        vm.label(verifier, "Verifier");

        // Deploy a mock WFI token and mint total supply to the owner
        vm.startPrank(owner);
        wfiToken = new ERC20Mock("WeChain Token", "WFI", owner, totalSupply);
        vm.stopPrank();

        // Set the launch timestamp to the current block timestamp + 1 hour
        launchTimestamp = block.timestamp + 1 hours;

        // Deploy the WFIDistributor contract
        vm.startPrank(owner);
        distributorContract = new WFIDistributor(owner, IERC20(address(wfiToken)), launchTimestamp, verifier);
        vm.stopPrank();

        // Transfer tokens to the distribution contract
        vm.startPrank(owner);
        wfiToken.transfer(address(distributorContract), distributorContract.TOTAL_POOL_AMOUNT());
        vm.stopPrank();
    }

    /**
     * @notice Get a signature for testing purposes.
     */
    function getSignature(address claimedFrom, uint256 amount, uint256 validUntil) public view returns (bytes memory) {
        // Verify if provided arguments and signature are valid and matching
        bytes32 msgHash = MessageHashUtils.toEthSignedMessageHash(keccak256(abi.encodePacked(claimedFrom, amount, validUntil)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);
        console.logBytes(signature);
        return signature;
    }

    /**
     * @notice Test initialization and basic setup.
     */
    function testInitialization() public view {
        // Check initial state variables
        assertEq(distributorContract.launchTimestamp(), launchTimestamp);

        // Check the WFI token balance of the distribution contract
        uint256 contractBalance = wfiToken.balanceOf(address(distributorContract));
        assertEq(contractBalance, distributorContract.TOTAL_POOL_AMOUNT());
    }

    /**
     * @notice Test claiming mining rewards before the launch timestamp.
     */
    function testCannotClaimMiningRewardsBeforeLaunch() public {
        vm.startPrank(user);
        uint256 amount = 100 * 1e18;
        uint256 validUntil = block.timestamp + 100;
        bytes memory signature = getSignature(user, amount, validUntil);
        vm.expectRevert("Distribution has not started yet");
        distributorContract.claimMiningRewards(amount, validUntil, user, signature);
        vm.stopPrank();
    }

    /**
     * @notice Test claiming referral rewards before the launch timestamp.
     */
    function testCannotClaimReferralRewardsBeforeLaunch() public {
        vm.startPrank(user);
        uint256 amount = 100 * 1e18;
        uint256 validUntil = block.timestamp + 100;
        bytes memory signature = getSignature(user, amount, validUntil);
        vm.expectRevert("Distribution has not started yet");
        distributorContract.claimReferralRewards(amount, validUntil, user, signature);
        vm.stopPrank();
    }

    /**
     * @notice Test claiming mining rewards after launch.
     */
    function testClaimMiningRewards() public {
        // Warp to just after launch timestamp
        vm.warp(launchTimestamp + 100);

        // Calculate expected rewards
        uint256 elapsedTime = block.timestamp - launchTimestamp;
        uint256 expectedReward = elapsedTime * 8 * 1e18; // First interval emission rate

        uint256 amount = expectedReward;
        uint256 validUntil = block.timestamp + 100;
        bytes memory signature = getSignature(user, amount, validUntil);
        vm.startPrank(user);
        distributorContract.claimMiningRewards(amount, validUntil, user, signature);
        vm.stopPrank();

        // Check user's WFI token balance
        uint256 userBalance = wfiToken.balanceOf(user);
        assertEq(userBalance, expectedReward);

        // Check totalMiningDistributed
        uint256 totalDistributed = distributorContract.totalMiningDistributed();
        assertEq(totalDistributed, expectedReward);

        // Check claim data
        (address receiver, uint256 claimAmount) = distributorContract.claims(signature);
        assertEq(receiver, user);
        assertEq(claimAmount, amount);
    }

    /**
     * @notice Test claiming referral rewards after launch.
     */
    function testClaimReferralRewards() public {
        // Warp to just after launch timestamp
        vm.warp(launchTimestamp + 100);

        // Calculate expected rewards
        uint256 elapsedTime = block.timestamp - launchTimestamp;
        uint256 totalVested = (distributorContract.REFERRAL_STAKING_POOL() * elapsedTime) / (730 days);
        uint256 expectedReward = totalVested;

        uint256 amount = expectedReward;
        uint256 validUntil = block.timestamp + 100;
        bytes memory signature = getSignature(user, amount, validUntil);
        vm.startPrank(user);
        distributorContract.claimReferralRewards(amount, validUntil, user, signature);
        vm.stopPrank();

        // Check user's WFI token balance
        uint256 userBalance = wfiToken.balanceOf(user);
        assertEq(userBalance, expectedReward);

        // Check totalReferralDistributed
        uint256 totalDistributed = distributorContract.totalReferralDistributed();
        assertEq(totalDistributed, expectedReward);

        // Check claim data
        (address receiver, uint256 claimAmount) = distributorContract.claims(signature);
        assertEq(receiver, user);
        assertEq(claimAmount, amount);
    }

    /**
     * @notice Test pausing and unpausing the contract.
     */
    function testPauseAndUnpause() public {
        // Warp to after launch
        vm.warp(launchTimestamp + 100);

        // Pause the contract
        vm.startPrank(owner);
        distributorContract.pause();
        vm.stopPrank();

        uint256 amount1 = 100 * 1e18;
        uint256 validUntil1 = block.timestamp + 100;
        bytes memory signature1 = getSignature(user, amount1, validUntil1);

        // Attempt to claim rewards while paused
        vm.startPrank(user);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        distributorContract.claimMiningRewards(amount1, validUntil1, user, signature1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        distributorContract.claimReferralRewards(amount1, validUntil1, user, signature1);
        vm.stopPrank();

        // Unpause the contract
        vm.startPrank(owner);
        distributorContract.unpause();
        vm.stopPrank();

        // Claim rewards after unpausing
        vm.startPrank(user);
        distributorContract.claimMiningRewards(amount1, validUntil1, user, signature1);

        uint256 amount2 = 10 * 1e18;
        uint256 validUntil2 = block.timestamp + 10;
        bytes memory signature2 = getSignature(user, amount2, validUntil2);
        distributorContract.claimReferralRewards(amount2, validUntil2, user, signature2);
        vm.stopPrank();

        // Check balances to ensure rewards were received
        uint256 userBalance = wfiToken.balanceOf(user);
        assertTrue(userBalance > 0);
    }

    /**
     * @notice Test transferring remaining tokens after distribution period.
     */
    function testTransferRemainingTokens() public {
        vm.warp(launchTimestamp + 1);

        // Attempt to transfer remaining tokens
        vm.startPrank(owner);
        vm.expectRevert("Blockchain migration has not been set yet");
        distributorContract.transferRemainingTokens(treasury);

        uint256 totalUnlockedMiningBefore = distributorContract.totalUnlockedMiningRewards();
        uint256 totalUnlockedReferralsBefore = distributorContract.totalUnlockedReferralRewards();
        console.log("totalUnlockedMiningBefore", totalUnlockedMiningBefore);
        console.log("totalUnlockedReferralsBefore", totalUnlockedReferralsBefore);
        assertEq(totalUnlockedMiningBefore, distributorContract.tokensPerSecond(0));
        assertEq(totalUnlockedReferralsBefore, distributorContract.REFERRAL_STAKING_POOL() / 730 days);

        vm.expectRevert("Timestamp must be at least 7 days in the future, to let users claim their rewards");
        distributorContract.setBlockchainMigrationTimestamp(block.timestamp + 1 days);

        distributorContract.setBlockchainMigrationTimestamp(block.timestamp + 7 days);

        vm.expectRevert("Blockchain migration has not been completed yet");
        distributorContract.transferRemainingTokens(treasury);

        vm.warp(block.timestamp + 7 days + 1);

        uint256 totalUnlockedMiningAfter = distributorContract.totalUnlockedMiningRewards();
        uint256 totalUnlockedReferralsAfter = distributorContract.totalUnlockedReferralRewards();
        console.log("totalUnlockedMiningAfter", totalUnlockedMiningAfter);
        console.log("totalUnlockedReferralsAfter", totalUnlockedReferralsAfter);
        assertEq(totalUnlockedMiningAfter, totalUnlockedMiningBefore);
        assertEq(totalUnlockedReferralsAfter, totalUnlockedReferralsBefore);

        distributorContract.transferRemainingTokens(treasury);
        vm.stopPrank();

        // Check treasury balance
        uint256 treasuryBalance = wfiToken.balanceOf(treasury);
        console.log("treasuryBalance", treasuryBalance);
        assertEq(treasuryBalance, totalUnlockedMiningBefore + totalUnlockedReferralsBefore);
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
     * @notice Test that claiming rewards cannot exceed the allocated pools.
     */
    function testCannotExceedAllocatedPools() public {
        // Warp to after the entire mining duration
        uint256 miningDuration = distributorContract.miningRewardsDuration();
        vm.warp(launchTimestamp + miningDuration + 1);

        uint256 amount = 100 * 1e18;
        uint256 validUntil = block.timestamp + 100;
        bytes memory signature = getSignature(user, amount, validUntil);
        vm.startPrank(user);
        distributorContract.claimMiningRewards(amount, validUntil, user, signature);
        vm.stopPrank();

        // Attempt to claim again should result in a revert
        vm.startPrank(user);
        vm.expectRevert("Claim already exists");
        distributorContract.claimMiningRewards(amount, validUntil, user, signature);
        vm.stopPrank();

        // Total distributed should equal the user's balance
        uint256 totalDistributed = distributorContract.totalMiningDistributed();
        uint256 actualUserBalance = wfiToken.balanceOf(user);
        assertEq(totalDistributed, actualUserBalance);
    }

    struct timestampReward {
        uint256 timestamp;
        uint256 expectedTotalReward;
    }

    function testCalculateMiningRewardsAtVariousTimestamps() public {
        // Initialize variables
        uint256 totalDistributed = 0;
        uint256 userBalance = 0;

        // Define test timestamps relative to launchTimestamp
        timestampReward[] memory testTimestamps = new timestampReward[](5);
        testTimestamps[0] = timestampReward(0, 0);
        testTimestamps[1] = timestampReward(1_000, 8_000 * 1e18);
        testTimestamps[2] = timestampReward(distributorContract.intervalDurations(0), 459_770_112 * 1e18);
        testTimestamps[3] = timestampReward(
            distributorContract.intervalDurations(0) + distributorContract.intervalDurations(1) / 2,
            459_770_112 * 1e18 + 114_942_528 * 1e18
        );
        testTimestamps[4] = timestampReward(distributorContract.miningRewardsDuration(), distributorContract.MINING_REWARDS_POOL());

        for (uint256 i = 0; i < testTimestamps.length; i++) {
            uint256 t = testTimestamps[i].timestamp;
            uint256 expectedTotalReward = testTimestamps[i].expectedTotalReward;

            console.log("warp to", launchTimestamp + t);
            // Warp to launchTimestamp + t
            vm.warp(launchTimestamp + t);

            // Calculate claimable amount
            uint256 claimable = expectedTotalReward - totalDistributed;

            console.log("expectedTotalReward", expectedTotalReward);

            if (claimable > 0) {
                // Check totalMiningDistributed
                uint256 actualTotalUnlocked = distributorContract.totalUnlockedMiningRewards();
                assertEq(actualTotalUnlocked, expectedTotalReward);

                // Attempt to claim the claimable amount
                uint256 amount = claimable;
                uint256 validUntil = block.timestamp + 1000;
                bytes memory signature = getSignature(user, amount, validUntil);
                vm.startPrank(user);
                distributorContract.claimMiningRewards(amount, validUntil, user, signature);
                vm.stopPrank();

                // Update tracking variables
                totalDistributed += amount;
                userBalance += amount;
                console.log("totalDistributed", totalDistributed);

                // Check user's WFI token balance
                uint256 actualUserBalance = wfiToken.balanceOf(user);
                assertEq(actualUserBalance, userBalance);

                // Check totalMiningDistributed
                uint256 actualTotalDistributed = distributorContract.totalMiningDistributed();
                assertEq(actualTotalDistributed, totalDistributed);
            } else {
                // Attempt to claim any amount should revert
                uint256 amount = 1 * 1e18;
                uint256 validUntil = block.timestamp + 1000;
                bytes memory signature = getSignature(user, amount, validUntil);
                vm.startPrank(user);

                // Adjust expected revert message based on the timestamp
                if (block.timestamp <= launchTimestamp) {
                    vm.expectRevert("Distribution has not started yet");
                } else {
                    vm.expectRevert("Amount exceeds claimable rewards");
                }

                distributorContract.claimMiningRewards(amount, validUntil, user, signature);
                vm.stopPrank();
            }
        }
    }

    function testCalculateReferralRewardsAtVariousTimestamps() public {
        // Initialize variables
        uint256 totalDistributed = 0;
        uint256 userBalance = 0;

        // Define test timestamps relative to launchTimestamp
        timestampReward[] memory testTimestamps = new timestampReward[](5);
        testTimestamps[0] = timestampReward(0, 0);
        testTimestamps[1] = timestampReward(1, 2_028_333_238_203_957_382);
        testTimestamps[2] = timestampReward(
            distributorContract.REFERRAL_VESTING_DURATION() / 4,
            distributorContract.REFERRAL_STAKING_POOL() / 4
        );
        testTimestamps[3] = timestampReward(
            distributorContract.REFERRAL_VESTING_DURATION() / 2,
            distributorContract.REFERRAL_STAKING_POOL() / 2
        );
        testTimestamps[4] = timestampReward(distributorContract.REFERRAL_VESTING_DURATION(), distributorContract.REFERRAL_STAKING_POOL());

        for (uint256 i = 0; i < testTimestamps.length; i++) {
            uint256 t = testTimestamps[i].timestamp;
            uint256 expectedTotalReward = testTimestamps[i].expectedTotalReward;

            console.log("warp to", launchTimestamp + t);
            // Warp to launchTimestamp + t
            vm.warp(launchTimestamp + t);

            // Calculate claimable amount
            uint256 claimable = expectedTotalReward - totalDistributed;

            console.log("expectedTotalReward", expectedTotalReward);

            if (claimable > 0) {
                // Check totalMiningDistributed
                uint256 actualTotalUnlocked = distributorContract.totalUnlockedReferralRewards();
                assertEq(actualTotalUnlocked, expectedTotalReward);

                // Attempt to claim the claimable amount
                uint256 amount = claimable;
                uint256 validUntil = block.timestamp + 1000;
                bytes memory signature = getSignature(user, amount, validUntil);
                vm.startPrank(user);
                distributorContract.claimReferralRewards(amount, validUntil, user, signature);
                vm.stopPrank();

                // Update tracking variables
                totalDistributed += amount;
                userBalance += amount;
                console.log("totalDistributed", totalDistributed);

                // Check user's WFI token balance
                uint256 actualUserBalance = wfiToken.balanceOf(user);
                assertEq(actualUserBalance, userBalance);

                // Check totalMiningDistributed
                uint256 actualTotalDistributed = distributorContract.totalReferralDistributed();
                assertEq(actualTotalDistributed, totalDistributed);
            } else {
                // Attempt to claim any amount should revert
                uint256 amount = 1 * 1e18;
                uint256 validUntil = block.timestamp + 1000;
                bytes memory signature = getSignature(user, amount, validUntil);
                vm.startPrank(user);

                // Adjust expected revert message based on the timestamp
                if (block.timestamp <= launchTimestamp) {
                    vm.expectRevert("Distribution has not started yet");
                } else {
                    vm.expectRevert("Amount exceeds claimable rewards");
                }

                distributorContract.claimReferralRewards(amount, validUntil, user, signature);
                vm.stopPrank();
            }
        }
    }
}
