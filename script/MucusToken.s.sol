// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import {Mucus} from "../src/Mucus.sol";
import {DividendsPairStaking} from "../src/DividendsPairStaking.sol";

contract MucusTokenScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address teamWallet = vm.envAddress("TEAM_WALLET");
        vm.startBroadcast(deployerPrivateKey);

        Mucus mucus = new Mucus(teamWallet);
        DividendsPairStaking dps = new DividendsPairStaking(address(mucus));

        vm.stopBroadcast();
    }
}
