// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract Staking {
    uint256 public nextSoupCycle = block.timestamp + 12 hours;

    constructor() {}
}
