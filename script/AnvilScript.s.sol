// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import {Mucus} from "../src/Mucus.sol";
import {MucusFarm} from "../src/MucusFarm.sol";
import {DividendsPairStaking} from "../src/DividendsPairStaking.sol";
import {FrogsAndDogs} from "../src/FrogsAndDogs.sol";

import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {VRFCoordinatorV2Mock} from "../test/mocks/VRFCoordinatorV2Mock.sol";
import {LinkTokenInterface} from "chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {VRFConsumerBaseV2} from "chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

contract AnvilScript is Script {
    uint96 constant _baseFee = 100000000000000000;
    uint96 constant _gasPriceLink = 1000000000;
    bytes32 constant _keyHash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;

    uint256 constant ETH_MINT_PRICE = 0.001 ether;
    bytes32 constant merkleRoot = 0x070e8db97b197cc0e4a1790c5e6c3667bab32d733db7f815fbe84f5824c7168d;

    function run() external {
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address teamWallet = vm.envAddress("TEAM_WALLET");

        vm.startBroadcast(deployerPrivateKey);

        Mucus mucus = new Mucus(teamWallet);
        DividendsPairStaking dps = new DividendsPairStaking(address(mucus));
        mucus.setDividendsPairStaking(address(dps));
        console.log("mucus and dividends pair staking deployed");
        console.log("mucus: %s", address(mucus));
        console.log("dps: %s", address(dps));
        console.log("block number: ", block.number);

        IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        // Liquidity amount calculation
        // (9393 / 3) - 1515 = 1616
        // ~10% for team
        // ~6% for investors
        uint256 tokenAmount = 1616 * 1e8 * 1e18;
        mucus.approve(address(router), tokenAmount);
        router.addLiquidityETH{value: 5 ether}(address(mucus), tokenAmount, 0, 0, address(this), block.timestamp + 360);
        console.log(
            "MUCUS/WETH uniswap pair address: ",
            IUniswapV2Factory(router.factory()).getPair(address(mucus), router.WETH())
        );

        VRFCoordinatorV2Mock vrfCoordinator = new VRFCoordinatorV2Mock(_baseFee, _gasPriceLink);
        uint64 _subscriptionId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(_subscriptionId, 1000 ether);
        console.log("subscription created and funded with 1000 ether: ", _subscriptionId);

        FrogsAndDogs fnd =
        new FrogsAndDogs(ETH_MINT_PRICE, merkleRoot, _subscriptionId, "", "", address(vrfCoordinator), _keyHash, address(mucus), address(dps));
        MucusFarm mucusFarm = new MucusFarm(address(fnd), address(mucus), address(dps));
        console.log("frogs and dogs deployed: ", address(fnd));
        console.log("mucus farm deployed: ", address(mucusFarm));

        mucus.setMucusFarm(address(mucusFarm));
        mucus.setFrogsAndDogs(address(fnd));

        fnd.setMucusFarm(address(mucusFarm));
        console.log("mucusFarm and fnd set for both the fnd and mucus contracts");

        vrfCoordinator.addConsumer(_subscriptionId, address(fnd));
        console.log("frogs and dogs contract added as consumer");

        vm.stopBroadcast();
    }
}
