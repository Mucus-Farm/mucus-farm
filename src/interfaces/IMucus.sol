// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMucus {
    event StakeAdded(address indexed staker, uint256 amount);
    event StakeRemoved(address indexed staker, uint256 amount);
    event DividendsPerShareUpdated(uint256 dividendsPerShare);

    function mint(address to, uint256 amount) external;
    function burn(address account, uint256 amount) external;
    function balanceOf(address owner) external view returns (uint256 balance);
    function setMucusFarm(address _mucusFarm) external;
    function withdraw() external;
}
