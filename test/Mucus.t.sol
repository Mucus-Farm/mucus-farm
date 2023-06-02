// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Mucus} from "../src/Mucus.sol";
import {DividendsPairStaking} from "../src/DividendsPairStaking.sol";
import {IDividendsPairStaking} from "../src/DividendsPairStaking.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";

contract Initial is Test {
    Mucus public mucus;
    DividendsPairStaking public dps;
    IUniswapV2Router02 public router;
    IUniswapV2Pair public pair;
    IERC20 public weth;

    uint256 public ethAmount = 100000000000 ether;
    uint256 public tokenAmount = 100000000000 ether;
    uint256 public swapTokensAtAmount = 278787 * 1e18;

    // router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    // pair = 0x8b4a31307634C995D7C6e3F5A30D0B272F56013a
    // weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2

    function setUp() public {
        vm.startPrank(address(1));
        address _uniswapRouter02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        mucus = new Mucus(_uniswapRouter02);
        dps = new DividendsPairStaking(address(mucus), _uniswapRouter02);
        mucus.setDividendsPairStaking(address(dps));

        router = IUniswapV2Router02(_uniswapRouter02);
        weth = IERC20(router.WETH());
        address _pair = IUniswapV2Factory(router.factory()).getPair(address(mucus), address(weth));
        pair = IUniswapV2Pair(_pair);

        vm.label(address(router), "Router");
        vm.label(address(pair), "Pair");
        vm.label(address(weth), "Weth");

        addLiquidity();
        vm.stopPrank();
    }

    function addLiquidity() public {
        deal(address(1), ethAmount);
        // approve token transfer to cover all possible scenarios
        mucus.approve(address(router), tokenAmount);

        // add the liquidity
        // add the liquidity
        router.addLiquidityETH{value: ethAmount}(
            address(mucus),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        assertEq(reserve0, weth.balanceOf(address(pair)), "initial weth reserves check");
        assertEq(reserve1, mucus.balanceOf(address(pair)), "initial mucus reserves check");
    }
}

contract MucusSwaps is Initial {
    function testBuyingMucus() public {
        uint256 bal = 1000 ether;
        hoax(address(2), bal);
        uint256 amountOut = 100 ether;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(mucus);
        router.swapETHForExactTokens{value: bal}(amountOut, path, address(2), block.timestamp);

        assertEq(mucus.balanceOf(address(pair)), tokenAmount - amountOut, "mucus reserves decreased");
        assertEq(mucus.balanceOf(address(mucus)), amountOut * 6 / 100, "mucus contract balance increased");
        assertEq(mucus.balanceOf(address(2)), amountOut * 94 / 100, "buyer mucus balance");
    }

    function testSellMucus() public {
        vm.prank(address(1));
        uint256 bal = 1000 ether;
        mucus.transfer(address(2), bal);
        uint256 amountIn = 100 ether;
        address[] memory path = new address[](2);
        path[0] = address(mucus);
        path[1] = address(weth);

        vm.startPrank(address(2));
        mucus.approve(address(router), amountIn);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, 0, path, address(2), block.timestamp);
        vm.stopPrank();

        assertEq(mucus.balanceOf(address(pair)), tokenAmount + (amountIn * 94 / 100), "mucus reserves increased");
        assertEq(mucus.balanceOf(address(mucus)), amountIn * 6 / 100, "mucus contract balance increased");
        assertEq(mucus.balanceOf(address(2)), bal - amountIn, "seller mucus balance");
    }
}

contract MucusSwapBack is Initial {
    function testSwapBack() public {
        hoax(address(1), 2000 ether);
        dps.addStake{value: 1000 ether}(IDividendsPairStaking.Faction.FROG);
        dps.addStake{value: 1000 ether}(IDividendsPairStaking.Faction.DOG);

        vm.prank(address(1));
        mucus.transfer(address(mucus), swapTokensAtAmount);

        vm.prank(address(1));
        uint256 bal = 1000 ether;
        mucus.transfer(address(2), bal);
        uint256 amountIn = 100 ether;
        address[] memory path = new address[](2);
        path[0] = address(mucus);
        path[1] = address(weth);

        vm.startPrank(address(2));
        mucus.approve(address(router), amountIn);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, 0, path, address(2), block.timestamp);
        vm.stopPrank();

        assertEq(mucus.balanceOf(address(pair)), tokenAmount + (amountIn * 94 / 100), "mucus reserves increased");
        assertEq(mucus.balanceOf(address(mucus)), amountIn * 6 / 100, "mucus contract balance increased");
        assertEq(mucus.balanceOf(address(2)), bal - amountIn, "seller mucus balance");
    }
}
