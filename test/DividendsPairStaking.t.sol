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
import {UniswapV2Library} from "./lib/UniswapV2Library.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

contract Initial is Test {
    Mucus public mucus;
    DividendsPairStaking public dps;
    IUniswapV2Router02 public router;
    IUniswapV2Pair public pair;
    IERC20 public weth;

    uint256 public ethAmount = 100000000000 ether;
    uint256 public tokenAmount = 100000000000 ether;
    uint256 public swapTokensAtAmount = 278787 * 1e18;

    IDividendsPairStaking.Faction frog = IDividendsPairStaking.Faction.FROG;
    IDividendsPairStaking.Faction dog = IDividendsPairStaking.Faction.DOG;

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
    }

    function formatEther(uint256 amount) public pure returns (uint256) {
        return amount / 1 ether;
    }
}

contract DpsConstructor is Initial {
    function testConstructor() public {
        (uint256 currentSoupIndex, uint256 soupCycleDuration, IDividendsPairStaking.SoupCycle memory previousSoupCycle,)
        = dps.getSoup(dps.currentSoupIndex());
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();

        assertEq(currentSoupIndex, 0, "currentSoupIndex");
        assertEq(soupCycleDuration, 3 days, "soupCycleDuration");
        assertEq(previousSoupCycle.timestamp, block.timestamp, "previousSoupCycle.timestamp");
        assertEq(uint256(previousSoupCycle.soupedUp), uint256(frog), "previousSoupCycle.soupedUp");
        assertEq(previousSoupCycle.totalFrogWins, 1, "previousSoupCycle.totalFrogWins");

        assertEq(reserve0, tokenAmount, "initial weth reserves check");
        assertEq(reserve1, ethAmount, "initial mucus reserves check");
    }
}

contract DpsStaking is Initial {
    event StakeAdded(address indexed staker, uint256 amount, IDividendsPairStaking.Faction faction);
    event StakeRemoved(address indexed staker, uint256 amount, IDividendsPairStaking.Faction faction);
    event DividendsPerShareUpdated(uint256 dividendsPerFrog, uint256 dividendsPerDog);
    event DividendsEarned(address indexed staker, uint256 amount);

    // function testInitialAddStake() public {
    //     vm.startPrank(address(2));

    //     deal(address(2), 1000 ether);
    //     uint256 ethToStake = 1000 ether;

    //     uint256 ethAmount = ethToStake >> 1;
    //     (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
    //     uint256 mucusAmount = UniswapV2Library.getAmountOut(ethAmount, reserve0, reserve1);

    //     uint256 reserve0AfterSwap = reserve0 - mucusAmount;
    //     uint256 reserve1AfterSwap = reserve1 + ethAmount;

    //     uint256 liquidity = UniswapV2Library.liquidityTokensMinted(
    //         address(pair), reserve0AfterSwap, reserve1AfterSwap, mucusAmount, ethAmount
    //     );

    //     vm.expectEmit(true, true, true, true);

    //     emit StakeAdded(address(2), liquidity, frog);

    //     dps.addStake{value: ethToStake}(frog);
    //     (
    //         uint256 totalAmount,
    //         uint256 frogFactionAmount,
    //         uint256 dogFactionAmount,
    //         uint256 previousDividendsPerFrog,
    //         uint256 previousDividendsPerDog,
    //         uint256 lockingEndDate
    //     ) = dps.stakers(address(2));

    //     vm.stopPrank();

    //     // dps assertions
    //     assertEq(pair.balanceOf(address(dps)), liquidity, "balance of dps");
    //     assertEq(totalAmount, liquidity, "totalAmount");
    //     assertEq(dps.totalStakedAmount(), liquidity, "totalStakedAmount");
    //     assertEq(dps.totalFrogFactionAmount(), liquidity, "totalFrogFactionAmount");
    //     assertEq(dps.totalDogFactionAmount(), 0, "totalDogFactionAmount");

    //     // staker assertions
    //     assertEq(frogFactionAmount, liquidity, "frogFactionAmount");
    //     assertEq(dogFactionAmount, 0, "dogFactionAmount");
    //     assertEq(previousDividendsPerFrog, 0, "previousDividendsPerFrog");
    //     assertEq(previousDividendsPerDog, 0, "previousDividendsPerDog");
    //     assertEq(lockingEndDate, block.timestamp + 2 weeks, "lockingEndDate");

    //     // claimed rewards
    //     assertEq(mucus.balanceOf(address(2)), 0, "mucus balance of staker");
    // }

    function testAddStakeAgain() public {
        vm.startPrank(address(2));

        deal(address(2), 2000 ether);
        uint256 ethToStake = 1000 ether;

        dps.addStake{value: ethToStake}(frog);

        uint256 initialLiquidity = pair.balanceOf(address(dps));

        uint256 ethAmount = ethToStake >> 1;
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();

        console.log("test reserves before the swap: ", reserve0, reserve1);

        uint256 mucusAmount = UniswapV2Library.getAmountOut(ethAmount, reserve0, reserve1);
        // console.log("test reserves: ", reserve0, reserve1);
        console.log("test amount: ", mucusAmount);
        // console.log("============");

        uint256 reserve0AfterSwap = reserve0 - mucusAmount;
        uint256 reserve1AfterSwap = reserve1 + 500 ether;
        console.log("test reserves after the swap: ", reserve0AfterSwap, reserve1AfterSwap);
        console.log(
            "test reserves after added liquidity: ", reserve0AfterSwap + mucusAmount, reserve1AfterSwap + ethAmount
        );
        console.log("======================");

        // uint256 addedLiquidity = UniswapV2Library.liquidityTokensMinted(
        //     address(pair), reserve0AfterSwap, reserve1AfterSwap, mucusAmount, 500 ether
        // );

        // console.log("added liquidity: ", addedLiquidity);
        // how much liquidity was actually added 498499997507500012462

        // vm.expectEmit(true, true, true, true);
        // emit DividendsEarned(address(2), 0);

        // vm.expectEmit(true, true, true, true);
        // emit StakeAdded(address(2), addedLiquidity, dog);

        dps.addStake{value: ethToStake}(dog);

        // (
        //     uint256 totalAmount,
        //     uint256 frogFactionAmount,
        //     uint256 dogFactionAmount,
        //     uint256 previousDividendsPerFrog,
        //     uint256 previousDividendsPerDog,
        //     uint256 lockingEndDate
        // ) = dps.stakers(address(2));

        // // dps assertions
        // assertEq(pair.balanceOf(address(dps)), initialLiquidity + addedLiquidity, "balance of dps");
        // assertEq(totalAmount, initialLiquidity + addedLiquidity, "totalAmount");
        // assertEq(dps.totalStakedAmount(), initialLiquidity + addedLiquidity, "totalStakedAmount");
        // assertEq(dps.totalFrogFactionAmount(), initialLiquidity, "totalFrogFactionAmount");
        // assertEq(dps.totalDogFactionAmount(), addedLiquidity, "totalDogFactionAmount");

        // // staker assertions
        // assertEq(frogFactionAmount, initialLiquidity, "frogFactionAmount");
        // assertEq(dogFactionAmount, addedLiquidity, "dogFactionAmount");
        // assertEq(previousDividendsPerFrog, 0, "previousDividendsPerFrog");
        // assertEq(previousDividendsPerDog, 0, "previousDividendsPerDog");
        // assertEq(lockingEndDate, block.timestamp + 2 weeks, "lockingEndDate");

        // // claimed rewards
        // assertEq(mucus.balanceOf(address(2)), 0, "mucus balance of staker");
    }

    // no rewards to claim
    // test when a user adds more onto an existing stake
    // test when a user partially removes a stake
    // test when a user fully removes a stake

    // rewards to claim
    // test when a user adds more onto an existing stake
    // test when a user partially removes a stake
    // test when a user fully removes a stake

    // voting

    // claim

    // cycleSoup

    // onlyOwner functions

    // external view functions
}
