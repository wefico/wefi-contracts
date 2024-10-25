// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract WFI is ERC20, Ownable, ERC20Permit {
    constructor(
        address initialOwner
    ) ERC20("WFI", "WFI") Ownable(initialOwner) ERC20Permit("WFI") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
