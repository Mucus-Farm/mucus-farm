// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import {IMucusFarm} from "../src/interfaces/IMucusFarm.sol";

contract SimStaking is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address teamWallet = vm.envAddress("TEAM_WALLET");
        address _mucusFarm = vm.envAddress("MUCUS_FARM_CONTRACT_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);

        IMucusFarm mucusFarm = IMucusFarm(_mucusFarm);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;
        mucusFarm.addManyToMucusFarm(0x5bb2610C42280674d6f70682f76311B44D1c07FB, tokenIds);
        console.log("successfully staked");

        vm.stopBroadcast();
    }
}
