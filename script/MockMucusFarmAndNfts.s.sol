// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import {IMucus} from "../src/interfaces/IMucus.sol";
import {MucusFarm} from "../src/MucusFarm.sol";
import {FrogsAndDogs} from "../src/FrogsAndDogs.sol";
import {VRFCoordinatorV2Mock} from "../test/mocks/VRFCoordinatorV2Mock.sol";
import {LinkTokenInterface} from "chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {VRFConsumerBaseV2} from "chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

contract MucusFarmAndNfts is Script {
    // TODO: swap out for mainnet for prod launch
    // bytes32 constant _keyHash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;
    // address constant _vrfCoordinator = 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D;
    // address constant _linkToken = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;

    uint96 constant _baseFee = 100000000000000000;
    uint96 constant _gasPriceLink = 1000000000;
    bytes32 constant _keyHash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;

    uint256 constant ETH_MINT_PRICE = 0.001 ether;
    bytes32 constant merkleRoot = bytes32(0x0);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address _mucus = vm.envAddress("MUCUS_CONTRACT_ADDRESS");
        address _dps = vm.envAddress("DPS_CONTRACT_ADDRESS");
        address teamWallet = vm.envAddress("TEAM_WALLET");

        vm.startBroadcast(deployerPrivateKey);

        VRFCoordinatorV2Mock vrfCoordinator = new VRFCoordinatorV2Mock(_baseFee, _gasPriceLink);
        uint64 _subscriptionId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(_subscriptionId, 1000 ether);
        console.log("subscription created and funded with 1 ether: ", _subscriptionId);

        IMucus mucus = IMucus(_mucus);
        FrogsAndDogs fnd =
        new FrogsAndDogs(ETH_MINT_PRICE, merkleRoot, _subscriptionId, "", "", address(vrfCoordinator), _keyHash, _mucus, _dps);
        MucusFarm mucusFarm = new MucusFarm(address(fnd), _mucus, _dps);
        console.log("frogs and dogs deployed: ", address(fnd));
        console.log("mucus farm deployed: ", address(mucusFarm));

        mucus.setMucusFarm(address(mucusFarm));
        mucus.setFrogsAndDogs(address(fnd));

        fnd.setMucusFarm(address(mucusFarm));
        fnd.setPublicMintStarted(); // TODO: remove this for production launch
        console.log("mucusFarm and fnd set for both the fnd and mucus contracts");

        vrfCoordinator.addConsumer(_subscriptionId, address(fnd));
        console.log("frogs and dogs contract added as consumer");

        vm.stopBroadcast();
    }
}
