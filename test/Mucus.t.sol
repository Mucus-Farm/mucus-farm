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
import {UniswapV2Library} from "./lib/UniswapV2Library.sol";

contract Initial is Test {
    Mucus public mucus;
    DividendsPairStaking public dps;
    IUniswapV2Router02 public router;
    IUniswapV2Pair public pair;
    IERC20 public weth;

    uint256 public ethAmount = 100000000000 ether;
    uint256 public tokenAmount = 100000000000 ether;
    uint256 public swapTokensAtAmount = 278787 * 1e18;

    uint16 public teamFee = 2;
    uint16 public stakerFee = 2;
    uint16 public liquidityFee = 2;
    uint16 public totalFee = teamFee + stakerFee + liquidityFee;

    address public teamWallet = address(123);
    address public owner = address(1);

    // router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    // pair = 0x8b4a31307634C995D7C6e3F5A30D0B272F56013a
    // weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 16183456);
        vm.startPrank(owner);
        address _uniswapRouter02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        mucus = new Mucus(teamWallet);
        dps = new DividendsPairStaking(address(mucus));
        mucus.setDividendsPairStaking(address(dps));

        router = IUniswapV2Router02(_uniswapRouter02);
        weth = IERC20(router.WETH());
        address _pair = IUniswapV2Factory(router.factory()).getPair(address(mucus), address(weth));
        pair = IUniswapV2Pair(_pair);

        vm.label(address(router), "Router");
        vm.label(address(pair), "Pair");
        vm.label(address(weth), "Weth");
        vm.label(owner, "Owner");
        vm.label(teamWallet, "TeamWallet");

        addLiquidity();
        vm.stopPrank();
    }

    function addLiquidity() public {
        deal(owner, ethAmount);
        // approve token transfer to cover all possible scenarios
        mucus.approve(address(router), tokenAmount);

        // add the liquidity
        router.addLiquidityETH{value: ethAmount}(
            address(mucus),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );

        (uint256 mucusReserve, uint256 ethReserve,) = pair.getReserves();
        assertEq(mucusReserve, weth.balanceOf(address(pair)), "initial weth reserves check");
        assertEq(ethReserve, mucus.balanceOf(address(pair)), "initial mucus reserves check");
    }

    function formatEther(uint256 amount) public pure returns (uint256) {
        return amount / 1 ether;
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
        vm.prank(owner);
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
        hoax(owner, 2000 ether);
        dps.addStake{value: 1000 ether}(IDividendsPairStaking.Faction.FROG);
        dps.addStake{value: 1000 ether}(IDividendsPairStaking.Faction.DOG);

        vm.prank(owner);
        uint256 bal = 1000 ether;
        mucus.transfer(address(2), bal);

        vm.prank(owner);
        mucus.transfer(address(mucus), swapTokensAtAmount);

        uint256 amountIn = 100 ether;
        address[] memory path = new address[](2);
        path[0] = address(mucus);
        path[1] = address(weth);

        // How much mucus and eth is getting swapped in the swapBack function
        uint256 mucusBalanceBefore = mucus.balanceOf(address(mucus));

        uint256 mucusSold = swapTokensAtAmount >> 1;
        (uint256 mucusReserveBefore, uint256 ethReserveBefore,) = IUniswapV2Pair(pair).getReserves();
        uint256 ethBought = UniswapV2Library.getAmountOut(mucusSold, mucusReserveBefore, ethReserveBefore);

        (uint256 mucusLiquidityAdded, uint256 ethLiquidityAdded) = UniswapV2Library.addLiquidityAmount(
            mucusReserveBefore + mucusSold, ethReserveBefore - ethBought, mucusBalanceBefore / 6, ethBought / 3, 0, 0
        );

        vm.startPrank(address(2));
        mucus.approve(address(router), amountIn);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, 0, path, address(2), block.timestamp);
        vm.stopPrank();

        (uint256 mucusReserveAfter, uint256 ethReserveAfter,) = IUniswapV2Pair(pair).getReserves();
        assertEq(
            mucus.balanceOf(address(mucus)),
            mucusBalanceBefore - mucusSold - mucusLiquidityAdded - (mucusBalanceBefore / 3) + (100 ether * 6 / 100),
            "mucus balance"
        );
        // assertEq(mucusReserveAfter, mucusReserveBefore + mucusSold + mucusLiquidityAdded, "mucus reserves");
        // assertEq(ethReserveAfter, ethReserveBefore + ethBought + ethLiquidityAdded, "eth reserves");
        assertEq(mucus.balanceOf(address(dps)), swapTokensAtAmount * 1 / 3, "dps mucus balance increased");
        assertEq(address(teamWallet).balance, (ethBought * 2 / 3) + 1, "team wallet balance increased"); // +1 for rounding error
        assertEq(address(mucus).balance, 0, "mucus eth balance drained");
    }
}

contract MucusOnlyOwner is Initial {
    function testSettingMucusFarm() public {
        vm.prank(owner);
        mucus.setMucusFarm(address(111));
        assertEq(mucus.mucusFarm(), address(111), "MucusFarm set");
    }

    function testSettingDividendsPairStaking() public {
        vm.prank(owner);
        mucus.setDividendsPairStaking(address(111));
        assertEq(address(mucus.dividendsPairStaking()), address(111), "dividendsPairStaking set");
    }
}
