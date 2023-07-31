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
    uint256 public swapTokensAtAmount = 313131 * 1e18;

    uint16 public stakerFee = 40;
    uint16 public teamFee = 10;
    uint16 public liquidityFee = 10;
    uint16 public totalFee = teamFee + stakerFee + liquidityFee;
    uint16 public denominator = 1000;

    address public teamWallet = address(123);
    address public owner = address(1);

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
    uint16 liquidityFeeHalf = liquidityFee >> 1;
    uint256 tokensForStakers = swapTokensAtAmount * stakerFee / totalFee;
    uint256 tokensForliquidity = swapTokensAtAmount * liquidityFeeHalf / totalFee;
    uint256 tokensToSwapForEth = swapTokensAtAmount - tokensForStakers - tokensForliquidity;

    function testSwapBack() public {
        hoax(owner, 1000 ether);
        dps.addStake{value: 1000 ether}(IDividendsPairStaking.Faction.FROG, 0);
        hoax(owner, 1000 ether);
        dps.addStake{value: 1000 ether}(IDividendsPairStaking.Faction.DOG, 0);

        vm.prank(owner);
        mucus.transfer(address(2), 1000 ether);

        vm.prank(owner);
        mucus.transfer(address(mucus), swapTokensAtAmount);

        uint256 amountIn = 100 ether;
        (uint256 mucusReserveBefore, uint256 ethReserveBefore,) = IUniswapV2Pair(pair).getReserves();
        uint256 ethBought = UniswapV2Library.getAmountOut(amountIn * 94 / 100, mucusReserveBefore, ethReserveBefore);

        uint256 ethBalance = UniswapV2Library.getAmountOut(tokensToSwapForEth, mucusReserveBefore, ethReserveBefore);
        mucusReserveBefore += tokensToSwapForEth;
        ethReserveBefore -= ethBalance;

        uint256 ethForLiquidity = ethBalance * liquidityFeeHalf / (liquidityFeeHalf + teamFee);
        uint256 ethForTeam = ethBalance - ethForLiquidity;
        (uint256 mucusLiquidityAdded, uint256 ethLiquidityAdded) = UniswapV2Library.addLiquidityAmount(
            mucusReserveBefore, ethReserveBefore, tokensForliquidity, ethForLiquidity, 0, 0
        );

        mucusReserveBefore += mucusLiquidityAdded;
        ethReserveBefore += ethLiquidityAdded;

        vm.startPrank(address(2));
        mucus.approve(address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(mucus);
        path[1] = address(weth);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, 0, path, address(2), block.timestamp);
        vm.stopPrank();
        (uint256 mucusReserveAfter, uint256 ethReserveAfter,) = IUniswapV2Pair(pair).getReserves();

        assertEq(
            mucus.balanceOf(address(mucus)),
            // the only discrepancy is the the amount of tokens being added for liqudiity may not be exact
            (tokensForliquidity - mucusLiquidityAdded) + (amountIn * 6 / 100),
            "mucus balance"
        );
        assertEq(mucusReserveAfter, mucusReserveBefore + (amountIn * 94 / 100), "mucus reserves");
        // assertEq(ethReserveAfter, ethReserveBefore - ethBought, "eth reserves");
        assertEq(mucus.balanceOf(address(dps)), tokensForStakers, "dps mucus balance increased");
        assertEq(address(teamWallet).balance, ethForTeam, "team wallet balance increased");
        assertEq(address(mucus).balance, 0, "mucus eth balance drained");
    }
}

contract MucusNotExternal is Initial {
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

    function testMint() public {
        vm.prank(address(2));
        vm.expectRevert();
        mucus.mint(address(2), 1000 ether);
    }

    function testBurn() public {
        vm.prank(address(2));
        vm.expectRevert();
        mucus.burn(address(2), 1000 ether);
    }
}
