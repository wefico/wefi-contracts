// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/WFI.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WFITest is Test {
    WFI public wfi;
    address owner = address(100);
    address user1 = address(200);

    function setUp() public {
        vm.startPrank(owner);
        wfi = new WFI(owner);
        vm.stopPrank();
    }

    function testMinting() public {
        assertEq(wfi.balanceOf(user1), 0);
        vm.prank(owner);
        assertEq(wfi.balanceOf(owner), wfi.MAX_SUPPLY());
    }
}
