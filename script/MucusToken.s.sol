// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import {Mucus} from "../src/Mucus.sol";
import {DividendsPairStaking} from "../src/DividendsPairStaking.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";

contract MucusTokenScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address teamWallet = vm.envAddress("TEAM_WALLET");
        vm.startBroadcast(deployerPrivateKey);

        Mucus mucus = new Mucus(teamWallet);
        DividendsPairStaking dps = new DividendsPairStaking(address(mucus));
        mucus.setDividendsPairStaking(address(dps));
        console.log("mucus and dividends pair staking deployed");
        console.log("mucus: %s", address(mucus));
        console.log("dps: %s", address(dps));

        IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uint256 tokenAmount = mucus.balanceOf(teamWallet);
        mucus.approve(address(router), tokenAmount);
        router.addLiquidityETH{value: 5 ether}(address(mucus), tokenAmount, 0, 0, address(this), block.timestamp + 360);
        console.log(
            "MUCUS/WETH uniswap pair address: ",
            IUniswapV2Factory(router.factory()).getPair(address(mucus), router.WETH())
        );

        vm.stopBroadcast();
    }
}
