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
        distributorContract = new WFIDistributor(
            owner,
            IERC20(address(wfiToken)),
            launchTimestamp,
            verifier
        );
        vm.stopPrank();

        // Transfer tokens to the distribution contract
        vm.startPrank(owner);
        wfiToken.transfer(address(distributorContract), distributorContract.TOTAL_POOL_AMOUNT());
        vm.stopPrank();
    }

    /**
     * @notice Get a signature for testing purposes.
     */
    function getSignature(
        address claimedFrom,
        uint256 amount,
        uint256 validUntil
    ) public view returns (bytes memory) {
        // Verify if provided arguments and signature are valid and matching
        bytes32 msgHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(abi.encodePacked(claimedFrom, amount, validUntil))
        );
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
        distributorContract.claimMiningRewards(amount, validUntil, signature);
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
        distributorContract.claimReferralRewards(amount, validUntil, signature);
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
        distributorContract.claimMiningRewards(amount, validUntil, signature);
        vm.stopPrank();

        // Check user's WFI token balance
        uint256 userBalance = wfiToken.balanceOf(user);
        assertEq(userBalance, expectedReward);

        // Check totalMiningDistributed
        uint256 totalDistributed = distributorContract.totalMiningDistributed();
        assertEq(totalDistributed, expectedReward);

        // Check claim data
        (
            address claimedFrom,
            uint256 claimTimestamp,
            uint256 claimValidUntil,
            uint256 claimAmount
        ) = distributorContract.claims(signature);
        assertEq(claimedFrom, user);
        assertEq(claimTimestamp, block.timestamp);
        assertEq(claimValidUntil, validUntil);
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
        uint256 totalVested = (distributorContract.REFERRAL_STAKING_POOL() * elapsedTime) /
            (730 days);
        uint256 expectedReward = totalVested;

        uint256 amount = expectedReward;
        uint256 validUntil = block.timestamp + 100;
        bytes memory signature = getSignature(user, amount, validUntil);
        vm.startPrank(user);
        distributorContract.claimReferralRewards(amount, validUntil, signature);
        vm.stopPrank();

        // Check user's WFI token balance
        uint256 userBalance = wfiToken.balanceOf(user);
        assertEq(userBalance, expectedReward);

        // Check totalReferralDistributed
        uint256 totalDistributed = distributorContract.totalReferralDistributed();
        assertEq(totalDistributed, expectedReward);

        // Check claim data
        (
            address claimedFrom,
            uint256 claimTimestamp,
            uint256 claimValidUntil,
            uint256 claimAmount
        ) = distributorContract.claims(signature);
        assertEq(claimedFrom, user);
        assertEq(claimTimestamp, block.timestamp);
        assertEq(claimValidUntil, validUntil);
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
        distributorContract.claimMiningRewards(amount1, validUntil1, signature1);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        distributorContract.claimReferralRewards(amount1, validUntil1, signature1);
        vm.stopPrank();

        // Unpause the contract
        vm.startPrank(owner);
        distributorContract.unpause();
        vm.stopPrank();

        // Claim rewards after unpausing
        vm.startPrank(user);
        distributorContract.claimMiningRewards(amount1, validUntil1, signature1);

        uint256 amount2 = 10 * 1e18;
        uint256 validUntil2 = block.timestamp + 10;
        bytes memory signature2 = getSignature(user, amount2, validUntil2);
        distributorContract.claimReferralRewards(amount2, validUntil2, signature2);
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
        distributorContract.claimMiningRewards(amount, validUntil, signature);
        vm.stopPrank();

        // Attempt to claim again should result in a revert
        vm.startPrank(user);
        vm.expectRevert("Claim already exists");
        distributorContract.claimMiningRewards(amount, validUntil, signature);
        vm.stopPrank();

        // Total distributed should not exceed MINING_REWARDS_POOL
        uint256 totalDistributed = distributorContract.totalMiningDistributed();
        assertEq(totalDistributed, distributorContract.MINING_REWARDS_POOL());
    }
}
