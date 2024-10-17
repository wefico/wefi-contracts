// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/WFI.sol";

contract WFITest is Test {
	function testOwner() public pure {
		assertEq(address(1), address(1));
	}
}
