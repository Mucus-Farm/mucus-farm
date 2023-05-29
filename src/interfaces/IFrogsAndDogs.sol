// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.13;

interface IFrogsAndDogs {
    enum Faction {
        FROG,
        DOG
    }

    struct Request {
        uint256 amount;
        bool fulfilled;
        bool stake;
        bool transform;
        Faction transformationType;
        address parent;
    }

    event RequestSent(uint256 indexed RequestId, uint256 amount);
    event RequestFulfilled(uint256 indexed RequestId, uint256 amount);

    function mint(uint256 amount, bool stake) external payable;
    function breedAndAdopt(uint256 amount, bool stake) external payable;
    function transform(uint256[] calldata tokenIds, Faction transformationType, bool stake) external payable;
    function setMucusFarm(address _mucusFarm) external;
    function withdraw() external;
    function setPaused(bool _paused) external;
    function setBaseURI(string memory uri) external;
}
