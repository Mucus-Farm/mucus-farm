pragma solidity ^0.8.16;

import "forge-std/Test.sol";

contract StakedTest is Test {
    ArrMethods arr;
    MapMethods map;

    function setUp() public {
        arr = new ArrMethods();
        map = new MapMethods();
    }

    function test_runArr() public {
        uint256[] memory tokenIds = new uint256[](10);
        arr.addStake(tokenIds);
        map.addStake(tokenIds);

        arr.removeStake(5);
        map.removeStake(5);
    }
}

contract ArrMethods {
    uint256[] public staked;

    function addStake(uint256[] calldata tokenIds) external {
        uint256 l = tokenIds.length;
        for (uint256 i; i < l; i++) {
            staked.push(tokenIds[i]);
        }
    }

    function removeStake(uint256 index) public {
        uint256 last = staked[staked.length - 1];
        staked[index] = last;
        staked.pop();
    }
}

contract MapMethods {
    mapping(uint256 => uint256) public staked;
    uint256 public stakedLength;

    function addStake(uint256[] calldata tokenIds) external {
        uint256 l = tokenIds.length;
        for (uint256 i; i < l; i++) {
            staked[stakedLength + i] = tokenIds[i];
        }
        stakedLength += tokenIds.length;
    }

    function removeStake(uint256 index) public {
        uint256 last = staked[stakedLength - 1];
        staked[index] = last;
        stakedLength--;
    }
}
