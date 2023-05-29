// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IDividendsPairStaking {
    enum Faction {
        DOG,
        FROG
    }

    struct Staker {
        uint256 totalAmount;
        uint256 dogFactionAmount;
        uint256 frogFactionAmount;
        uint256 previousDividendsPerShare;
        uint256 lockingEndDate;
    }

    struct SoupCycle {
        uint256 timestamp;
        Faction soupedUp;
        uint256 totalFrogWins;
    }

    event StakeAdded(address indexed staker, uint256 amount);
    event StakeRemoved(address indexed staker, uint256 amount);
    event DividendsPerShareUpdated(uint256 dividendsPerShare);

    function nextSoupCycle() external view returns (uint256);
    function currentSoupIndex() external view returns (uint256);
    function addStake(uint256 amount, Faction faction) external;
    function removeStake(uint256 amount, Faction faction) external;
    function removeEntireStake() external;
    function claim() external;
    function deposit(uint256 amount) external;
    function cycleSoup() external;
    function getSoup(uint256 previousSoupIndex)
        external
        view
        returns (uint256, uint256, SoupCycle memory, SoupCycle memory);
    function withdraw() external;
}
