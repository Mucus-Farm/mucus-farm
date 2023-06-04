// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DividendsPairStaking} from "src/DividendsPairStaking.sol";
import {Mucus} from "src/Mucus.sol";
import {IDividendsPairStaking} from "src/interfaces/IDividendsPairStaking.sol";
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

    uint256 frog = uint256(IDividendsPairStaking.Faction.FROG);
    uint256 dog = uint256(IDividendsPairStaking.Faction.DOG);

    address public teamWallet = address(123);
    address public owner = address(1);

    function setUp() public {
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

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        assertEq(reserve0, tokenAmount, "initial weth reserves check");
        assertEq(reserve1, ethAmount, "initial mucus reserves check");
    }

    function formatEther(uint256 amount) public pure returns (uint256) {
        return amount / 1 ether;
    }
}

contract DpsConstructor is Initial {
    function testConstructor() public {
        (
            uint256 currentSoupIndex,
            uint256 soupCycleDuration,
            IDividendsPairStaking.SoupCycle memory previousSoupCycle,
            IDividendsPairStaking.SoupCycle memory currentSoupCycle
        ) = dps.getSoup(dps.currentSoupIndex());

        assertEq(currentSoupIndex, 0, "currentSoupIndex");
        assertEq(soupCycleDuration, 3 days, "soupCycleDuration");
        assertEq(previousSoupCycle.timestamp, block.timestamp, "previousSoupCycle.timestamp");
        assertEq(uint256(previousSoupCycle.soupedUp), frog, "previousSoupCycle.soupedUp");
        assertEq(previousSoupCycle.totalFrogWins, 1, "previousSoupCycle.totalFrogWins");
    }
}
