// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.13;

interface IFrogsAndDogs {
    enum Faction {
        DOG,
        FROG
    }

    struct Request {
        uint256 amount;
        bool transform;
        Faction transformationType;
        address parent;
    }

    event Transformation(address indexed parent, uint256 indexed tokenId, bool transformSucceeded);

    function mint(uint256 amount) external payable;
    function breedAndAdopt(uint256 amount) external payable;
    function transform(uint256[] calldata tokenIds, Faction transformationType) external payable;
    function setMucusFarm(address _mucusFarm) external;
    function withdraw() external;
    function setPaused(bool _paused) external;
    function setBaseURI(string memory uri) external;
}
