// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract WFI is Ownable {
    constructor(address _newOwner) Ownable(_newOwner) {}
}
