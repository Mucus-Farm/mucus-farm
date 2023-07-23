// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import {IFrogsAndDogs} from "../src/interfaces/IFrogsAndDogs.sol";
import {IMucusFarm} from "../src/interfaces/IMucusFarm.sol";

contract SimMinting is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address teamWallet = vm.envAddress("TEAM_WALLET");
        address _fnd = vm.envAddress("FND_CONTRACT_ADDRESS");
        address _mucusFarm = vm.envAddress("MUCUS_FARM_CONTRACT_ADDRESS");
        uint256 ETH_MINT_PRICE = 0.001 ether;
        vm.startBroadcast(deployerPrivateKey);

        IFrogsAndDogs fnd = IFrogsAndDogs(_fnd);
        IMucusFarm mucusFarm = IMucusFarm(_mucusFarm);

        fnd.mint{value: ETH_MINT_PRICE}(1, true);

        vm.stopBroadcast();
    }
}
