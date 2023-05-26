// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract LPStaking {
    uint256 public DogFactionAmount;
    uint256 public FrogFactionAmount;

    event StakeAdded(address indexed staker, uint256 amount);
    event StakeRemoved(address indexed staker, uint256 amount);
    event DividendsPerShareUpdated(uint256 dividendsPerShare);

    struct Staker {
        uint256 amount;
        uint256 previousDividendsPerShare;
        uint256 lockingEndDate;
    }

    uint256 public dividendsPerShare;
    mapping(address => Staker) public stakers;
    uint256 public totalStakedAmount;
    IERC20 public LPToken;

    constructor() {
        LPToken = IERC20(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    }
}
