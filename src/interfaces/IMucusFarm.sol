// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMucusFarm {
    enum Faction {
        DOG,
        FROG
    }

    struct Stake {
        address owner;
        uint256 lockingEndTime;
        uint256 previousClaimTimestamp; // for the case of a giga or a chad, needs to take either the preivousClaimTimestamp or the lastSoupCycle, whichever is bigger is what's subbed
        uint256 previousTaxPer;
        uint256 previousSoupIndex;
        uint256 gigaChadIndex;
    }

    event TokensStaked(address indexed parent, uint256[] tokenIds);
    event TokensUnstaked(address indexed parent, uint256[] tokenIds);
    event TokensFarmed(address indexed parent, uint256 mucusFarmed, uint256[] tokenIds);
    event MucusEarned(address indexed to, uint256 amount);

    function addManyToMucusFarm(uint256[] memory tokenIds) external;
    function claimMany(uint256[] memory tokenIds, bool unstake) external;
    function rescue(uint256[] calldata tokenIds) external;
    function setPaused(bool _paused) external;
    function randomGigaOrChad(uint256 seed, Faction faction) external view returns (address);
}
