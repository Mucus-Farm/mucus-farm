// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import {IDividendsPairStaking} from "../src/interfaces/IDividendsPairStaking.sol";

contract SimStaking is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address teamWallet = vm.envAddress("TEAM_WALLET");
        address dpsAddress = vm.envAddress("DPS_CONTRACT_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);

        IDividendsPairStaking dps = IDividendsPairStaking(dpsAddress);

        // dps.addStake{value: 1 ether}(IDividendsPairStaking.Faction.DOG, 0);
        dps.removeStake(81717109288160843143993, IDividendsPairStaking.Faction.DOG);

        (
            uint256 totalAmount,
            uint256 frogFactionAmount,
            uint256 dogFactionAmount,
            uint256 previousDividendsPerFrog,
            uint256 previousDividendsPerDog,
            uint256 lockingEndDate
        ) = dps.stakers(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

        console.log("total amount: ", totalAmount);
        console.log("frog amount: ", frogFactionAmount);
        console.log("dog amount: ", dogFactionAmount);

        vm.stopBroadcast();
    }
}
