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
    uint256 public swapTokensAtAmount = 313131 * 1e18;

    uint16 public stakerFee = 40;
    uint16 public teamFee = 10;
    uint16 public liquidityFee = 10;
    uint16 public totalFee = teamFee + stakerFee + liquidityFee;

    IDividendsPairStaking.Faction frog = IDividendsPairStaking.Faction.FROG;
    IDividendsPairStaking.Faction dog = IDividendsPairStaking.Faction.DOG;

    address public teamWallet = address(123);
    address public owner = address(1);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 16183456);
        vm.startPrank(owner);
        address _uniswapRouter02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        mucus = new Mucus(teamWallet);
        dps = new DividendsPairStaking(address(mucus));
        mucus.setDividendsPairStaking(address(dps));
        mucus.disableLimitsInEffect();

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
        (uint256 mucusReserve, uint256 ethReserve,) = pair.getReserves();

        assertEq(currentSoupIndex, 0, "currentSoupIndex");
        assertEq(soupCycleDuration, 3 days, "soupCycleDuration");
        assertEq(previousSoupCycle.timestamp, block.timestamp, "previousSoupCycle.timestamp");
        assertEq(uint256(previousSoupCycle.soupedUp), uint256(frog), "previousSoupCycle.soupedUp");
        assertEq(previousSoupCycle.totalFrogWins, 1, "previousSoupCycle.totalFrogWins");

        assertEq(mucusReserve, tokenAmount, "initial weth reserves check");
        assertEq(ethReserve, ethAmount, "initial mucus reserves check");
    }
}

contract DpsStaking is Initial {
    event StakeAdded(address indexed staker, uint256 amount, IDividendsPairStaking.Faction faction);
    event StakeRemoved(address indexed staker, uint256 amount, IDividendsPairStaking.Faction faction);
    event DividendsEarned(address indexed staker, uint256 amount);

    function testInitialAddStake() public {
        vm.startPrank(address(2));

        deal(address(2), 1000 ether);
        uint256 ethToStake = 1000 ether;

        uint256 ethAmount = ethToStake >> 1;
        (uint256 mucusReserve, uint256 ethReserve,) = pair.getReserves();
        uint256 mucusAmount = UniswapV2Library.getAmountOut(ethAmount, ethReserve, mucusReserve);

        uint256 mucusReserveAfterSwap = mucusReserve - mucusAmount;
        uint256 ethReserveAfterSwap = ethReserve + ethAmount;

        uint256 liquidity = UniswapV2Library.liquidityTokensMinted(
            address(pair), mucusReserveAfterSwap, ethReserveAfterSwap, mucusAmount, ethAmount
        );

        vm.expectEmit(true, true, true, true);

        emit StakeAdded(address(2), liquidity, frog);

        dps.addStake{value: ethToStake}(frog, 0);
        (
            uint256 totalAmount,
            uint256 frogFactionAmount,
            uint256 dogFactionAmount,
            uint256 previousDividendsPerFrog,
            uint256 previousDividendsPerDog,
            uint256 lockingEndDate
        ) = dps.stakers(address(2));

        vm.stopPrank();

        // dps assertions
        assertEq(pair.balanceOf(address(dps)), liquidity, "balance of dps");
        assertEq(totalAmount, liquidity, "totalAmount");
        assertEq(dps.totalStakedAmount(), liquidity, "totalStakedAmount");
        assertEq(dps.totalFrogFactionAmount(), liquidity, "totalFrogFactionAmount");
        assertEq(dps.totalDogFactionAmount(), 0, "totalDogFactionAmount");

        // staker assertions
        assertEq(frogFactionAmount, liquidity, "frogFactionAmount");
        assertEq(dogFactionAmount, 0, "dogFactionAmount");
        assertEq(previousDividendsPerFrog, 0, "previousDividendsPerFrog");
        assertEq(previousDividendsPerDog, 0, "previousDividendsPerDog");
        assertEq(lockingEndDate, block.timestamp + 2 weeks, "lockingEndDate");

        // claimed rewards
        assertEq(mucus.balanceOf(address(2)), 0, "mucus balance of staker");
    }

    function testAddStakeAgain() public {
        vm.startPrank(address(2));

        deal(address(2), 2000 ether);
        dps.addStake{value: 1000 ether}(frog, 0);

        uint256 initialLiquidity = pair.balanceOf(address(dps));
        (uint256 mucusReserve, uint256 ethReserve,) = pair.getReserves();

        uint256 mucusAmount = UniswapV2Library.getAmountOut(500 ether, ethReserve, mucusReserve);

        uint256 mucusReserveAfterSwap = mucusReserve - mucusAmount;
        uint256 ethReserveAfterSwap = ethReserve + 500 ether;

        uint256 addedLiquidity = UniswapV2Library.liquidityTokensMinted(
            address(pair), mucusReserveAfterSwap, ethReserveAfterSwap, mucusAmount, 500 ether
        );

        vm.expectEmit(true, true, true, true);
        emit DividendsEarned(address(2), 0);

        vm.expectEmit(true, true, true, true);
        emit StakeAdded(address(2), addedLiquidity, dog);

        dps.addStake{value: 1000 ether}(dog, 0);

        (
            uint256 totalAmount,
            uint256 frogFactionAmount,
            uint256 dogFactionAmount,
            uint256 previousDividendsPerFrog,
            uint256 previousDividendsPerDog,
            uint256 lockingEndDate
        ) = dps.stakers(address(2));

        // dps assertions
        assertEq(pair.balanceOf(address(dps)), initialLiquidity + addedLiquidity, "balance of dps");
        assertEq(totalAmount, initialLiquidity + addedLiquidity, "totalAmount");
        assertEq(dps.totalStakedAmount(), initialLiquidity + addedLiquidity, "totalStakedAmount");
        assertEq(dps.totalFrogFactionAmount(), initialLiquidity, "totalFrogFactionAmount");
        assertEq(dps.totalDogFactionAmount(), addedLiquidity, "totalDogFactionAmount");

        // staker assertions
        assertEq(frogFactionAmount, initialLiquidity, "frogFactionAmount");
        assertEq(dogFactionAmount, addedLiquidity, "dogFactionAmount");
        assertEq(previousDividendsPerFrog, 0, "previousDividendsPerFrog");
        assertEq(previousDividendsPerDog, 0, "previousDividendsPerDog");
        assertEq(lockingEndDate, block.timestamp + 2 weeks, "lockingEndDate");

        // claimed rewards
        assertEq(mucus.balanceOf(address(2)), 0, "mucus balance of staker");
    }

    function testPartiallyRemoveStake() public {
        vm.startPrank(address(2));

        deal(address(2), 1000 ether);
        dps.addStake{value: 1000 ether}(frog, 0);

        // error cases
        (uint256 initialTotalAmount, uint256 initialFrogFactionAmount, uint256 initialDogFactionAmount,,,) =
            dps.stakers(address(2));
        uint256 initialTotalAmountDps = dps.totalStakedAmount();
        uint256 initialFrogFactionAmountDps = dps.totalFrogFactionAmount();
        uint256 initialDogFactionAmountDps = dps.totalDogFactionAmount();

        vm.expectRevert(bytes("Amount must be greater than 0"));
        dps.removeStake(0, frog);

        vm.expectRevert(bytes("Cannot unstake more than you have staked"));
        dps.removeStake(initialTotalAmount + 1, frog);

        vm.expectRevert(bytes("Cannot unstake more than you have staked for the dog faction"));
        dps.removeStake(initialTotalAmount >> 1, dog);

        vm.expectRevert(bytes("Cannot unstake until locking period is over"));
        dps.removeStake(initialTotalAmount >> 1, frog);

        // test balance
        {
            uint256 liquidity = initialTotalAmount >> 1;
            (uint256 reserveMucusBefore, uint256 reserveEthBefore,) = pair.getReserves();
            uint256 liquidityBalanceBefore = pair.balanceOf(address(dps));

            (uint256 mucusRecieved, uint256 ethRecieved) =
                UniswapV2Library.removeLiquidityAmounts(address(pair), address(mucus), address(weth), liquidity);

            vm.warp(block.timestamp + 2 weeks + 1);

            vm.expectEmit(true, true, true, true);
            emit DividendsEarned(address(2), 0);

            vm.expectEmit(true, true, true, true);
            emit StakeRemoved(address(2), liquidity, frog);

            dps.removeStake(liquidity, frog);

            (uint256 reserveMucusAfter, uint256 reserveEthAfter,) = pair.getReserves();
            uint256 liquidityBalanceAfter = pair.balanceOf(address(dps));

            assertEq(liquidityBalanceBefore - liquidity, liquidityBalanceAfter, "liquidity balance of dps");
            assertEq(reserveMucusBefore - mucusRecieved, reserveMucusAfter, "mucus reserve");
            assertEq(reserveEthBefore - ethRecieved, reserveEthAfter, "eth reserve");
            assertEq(mucus.balanceOf(address(2)), mucusRecieved, "mucus balance of staker");
            assertEq(address(2).balance, ethRecieved, "eth balance of staker");
        }

        // test staker state
        {
            uint256 liquidity = initialTotalAmount >> 1;
            uint256 totalAmountBefore = initialTotalAmount;
            uint256 frogFactionAmountBefore = initialFrogFactionAmount;
            uint256 dogFactionAmountBefore = initialDogFactionAmount;
            (uint256 totalAmountAfter, uint256 frogFactionAmountAfter, uint256 dogFactionAmountAfter,,,) =
                dps.stakers(address(2));

            assertEq(totalAmountAfter, totalAmountBefore - liquidity, "staker total amount");
            assertEq(frogFactionAmountAfter, frogFactionAmountBefore - liquidity, "staker frog faction amount");
            assertEq(dogFactionAmountAfter, dogFactionAmountBefore, "staker dog faction amount");
        }

        {
            uint256 liquidity = initialTotalAmount >> 1;
            uint256 totalAmountBefore = initialTotalAmountDps;
            uint256 frogFactionAmountBefore = initialFrogFactionAmountDps;
            uint256 dogFactionAmountBefore = initialDogFactionAmountDps;
            uint256 totalAmountAfter = dps.totalStakedAmount();
            uint256 frogFactionAmountAfter = dps.totalFrogFactionAmount();
            uint256 dogFactionAmountAfter = dps.totalDogFactionAmount();

            assertEq(totalAmountAfter, totalAmountBefore - liquidity, "dps total amount");
            assertEq(frogFactionAmountAfter, frogFactionAmountBefore - liquidity, "dps frog faction amount");
            assertEq(dogFactionAmountAfter, dogFactionAmountBefore, "dps dog faction amount");
            assertEq(dps.totalStakedAmount(), totalAmountBefore - liquidity, "dps staked amount");
        }
    }

    function testFullyRemoveStake() public {
        vm.startPrank(address(2));

        deal(address(2), 1000 ether);
        dps.addStake{value: 1000 ether}(frog, 0);

        (uint256 liquidity,,,,,) = dps.stakers(address(2));

        // test balance
        {
            (uint256 reserveMucusBefore, uint256 reserveEthBefore,) = pair.getReserves();
            uint256 liquidityBalanceBefore = pair.balanceOf(address(dps));

            (uint256 mucusRecieved, uint256 ethRecieved) =
                UniswapV2Library.removeLiquidityAmounts(address(pair), address(mucus), address(weth), liquidity);

            vm.warp(block.timestamp + 2 weeks + 1);

            vm.expectEmit(true, true, true, true);
            emit DividendsEarned(address(2), 0);

            vm.expectEmit(true, true, true, true);
            emit StakeRemoved(address(2), liquidity, frog);

            dps.removeStake(liquidity, frog);
            vm.stopPrank();

            (uint256 reserveMucusAfter, uint256 reserveEthAfter,) = pair.getReserves();

            assertEq(liquidityBalanceBefore - liquidity, 0, "liquidity balance of dps");
            assertEq(reserveMucusBefore - mucusRecieved, reserveMucusAfter, "mucus reserve");
            assertEq(reserveEthBefore - ethRecieved, reserveEthAfter, "eth reserve");
            assertEq(mucus.balanceOf(address(2)), mucusRecieved, "mucus balance of staker");
            assertEq(address(2).balance, ethRecieved, "eth balance of staker");
        }

        // test staker state
        {
            (
                uint256 totalAmount,
                uint256 frogFactionAmount,
                uint256 dogFactionAmount,
                uint256 previousDividendsPerFrog,
                uint256 previousDividendsPerDog,
                uint256 lockingEndDate
            ) = dps.stakers(address(2));

            assertEq(totalAmount, 0, "staker total amount");
            assertEq(frogFactionAmount, 0, "staker frog faction amount");
            assertEq(dogFactionAmount, 0, "staker dog faction amount");
            assertEq(previousDividendsPerFrog, 0, "staker dividends per frog");
            assertEq(previousDividendsPerDog, 0, "staker dividends per frog");
            assertEq(lockingEndDate, 0, "staker locking end date");
        }

        {
            uint256 totalAmountAfter = dps.totalStakedAmount();
            uint256 frogFactionAmountAfter = dps.totalFrogFactionAmount();
            uint256 dogFactionAmountAfter = dps.totalDogFactionAmount();

            assertEq(totalAmountAfter, 0, "dps total amount");
            assertEq(frogFactionAmountAfter, 0, "dps frog faction amount");
            assertEq(dogFactionAmountAfter, 0, "dps dog faction amount");
            assertEq(dps.totalStakedAmount(), 0, "dps total staked amount");
        }
    }

    function testRevertSlippage() public {
        vm.startPrank(address(2));

        deal(address(2), 1000 ether);
        uint256 ethToStake = 1000 ether;

        uint256 ethAmount = ethToStake >> 1;
        (uint256 mucusReserve, uint256 ethReserve,) = pair.getReserves();
        uint256 mucusAmount = UniswapV2Library.getAmountOut(ethAmount, ethReserve, mucusReserve);

        vm.expectRevert(bytes("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"));
        dps.addStake{value: ethToStake}(frog, mucusAmount + 1);
    }

    function testSlippageAccepted() public {
        vm.startPrank(address(2));

        deal(address(2), 1000 ether);
        uint256 ethToStake = 1000 ether;

        uint256 ethAmount = ethToStake >> 1;
        (uint256 mucusReserve, uint256 ethReserve,) = pair.getReserves();
        uint256 mucusAmount = UniswapV2Library.getAmountOut(ethAmount, ethReserve, mucusReserve);

        uint256 mucusReserveAfterSwap = mucusReserve - mucusAmount;
        uint256 ethReserveAfterSwap = ethReserve + ethAmount;

        uint256 liquidity = UniswapV2Library.liquidityTokensMinted(
            address(pair), mucusReserveAfterSwap, ethReserveAfterSwap, mucusAmount, ethAmount
        );

        vm.expectEmit(true, true, true, true);

        emit StakeAdded(address(2), liquidity, frog);

        dps.addStake{value: ethToStake}(frog, mucusAmount);
        (uint256 totalAmount,,,,,) = dps.stakers(address(2));

        vm.stopPrank();

        // dps assertions
        assertEq(pair.balanceOf(address(dps)), liquidity, "balance of dps");
        assertEq(totalAmount, liquidity, "totalAmount");
    }
}

contract DpsVoting is Initial {
    event VoteSwapped(address indexed staker, uint256 amount, IDividendsPairStaking.Faction faction);

    function testSwapHalfFrogVotesToDog() public {
        vm.startPrank(address(2));
        vm.deal(address(2), 1000 ether);

        vm.expectRevert(bytes("Cannot vote if you haven't staked"));
        dps.vote(1, dog);

        dps.addStake{value: 1000 ether}(frog, 0);

        (, uint256 frogFactionAmountBefore, uint256 dogFactionAmountBefore,,,) = dps.stakers(address(2));
        uint256 totalFrogFactionAmountBefore = dps.totalFrogFactionAmount();
        uint256 totalDogFactionAmountBefore = dps.totalDogFactionAmount();
        uint256 vote = frogFactionAmountBefore >> 1;

        vm.expectRevert(bytes("Amount must be greater than 0"));
        dps.vote(0, dog);

        vm.expectRevert(bytes("Cannot swap more Frog votes than you have staked"));
        dps.vote(frogFactionAmountBefore + 1, dog);

        vm.expectRevert(bytes("Cannot swap more Dog votes than you have staked"));
        dps.vote(dogFactionAmountBefore + 1, frog);

        vm.expectEmit(true, true, true, true);
        emit VoteSwapped(address(2), vote, dog);

        dps.vote(vote, dog);

        // test staker state
        {
            (, uint256 frogFactionAmountAfter, uint256 dogFactionAmountAfter,,,) = dps.stakers(address(2));
            assertEq(frogFactionAmountAfter, frogFactionAmountBefore - vote, "staker frogFactionAmount");
            assertEq(dogFactionAmountAfter, dogFactionAmountBefore + vote, "staker dogFactionAmount");
        }

        // test dps state
        {
            assertEq(dps.totalFrogFactionAmount(), totalFrogFactionAmountBefore - vote, "dps FrogFactionAmount");
            assertEq(dps.totalDogFactionAmount(), totalDogFactionAmountBefore + vote, "dps dogFactionAmount");
        }
    }

    function testSwapAllFrogVotesToDog() public {
        vm.startPrank(address(2));
        vm.deal(address(2), 1000 ether);

        vm.expectRevert(bytes("Cannot vote if you haven't staked"));
        dps.vote(1, dog);

        dps.addStake{value: 1000 ether}(frog, 0);

        (, uint256 frogFactionAmountBefore, uint256 dogFactionAmountBefore,,,) = dps.stakers(address(2));

        vm.expectRevert(bytes("Amount must be greater than 0"));
        dps.vote(0, dog);

        vm.expectRevert(bytes("Cannot swap more Frog votes than you have staked"));
        dps.vote(frogFactionAmountBefore + 1, dog);

        vm.expectRevert(bytes("Cannot swap more Dog votes than you have staked"));
        dps.vote(dogFactionAmountBefore + 1, frog);

        vm.expectEmit(true, true, true, true);
        emit VoteSwapped(address(2), frogFactionAmountBefore, dog);

        console.log("frog faction amount before: ", frogFactionAmountBefore);
        dps.vote(frogFactionAmountBefore, dog);

        // test staker state
        {
            (, uint256 frogFactionAmountAfter, uint256 dogFactionAmountAfter,,,) = dps.stakers(address(2));
            assertEq(frogFactionAmountAfter, 0, "staker frogFactionAmount");
            assertEq(dogFactionAmountAfter, frogFactionAmountBefore, "staker dogFactionAmount");
        }

        // test dps state
        {
            assertEq(dps.totalFrogFactionAmount(), 0, "dps FrogFactionAmount");
            assertEq(dps.totalDogFactionAmount(), frogFactionAmountBefore, "dps dogFactionAmount");
        }
    }
}

contract DpsDistributeDividends is Initial {
    event StakeAdded(address indexed staker, uint256 amount, IDividendsPairStaking.Faction faction);
    event StakeRemoved(address indexed staker, uint256 amount, IDividendsPairStaking.Faction faction);
    event DividendsPerShareUpdated(uint256 dividendsPerFrog, uint256 dividendsPerDog);
    event DividendsEarned(address indexed staker, uint256 amount);

    function triggerSwapBack() public {
        hoax(owner, 2000 ether);
        dps.addStake{value: 1000 ether}(IDividendsPairStaking.Faction.FROG, 0);
        dps.addStake{value: 1000 ether}(IDividendsPairStaking.Faction.DOG, 0);

        vm.prank(owner);
        uint256 bal = 100 ether;
        mucus.transfer(address(2), bal);

        vm.prank(owner);
        mucus.transfer(address(mucus), swapTokensAtAmount);

        uint256 amountIn = 100 ether;
        address[] memory path = new address[](2);
        path[0] = address(mucus);
        path[1] = address(weth);

        vm.startPrank(address(2));
        mucus.approve(address(router), amountIn);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, 0, path, address(2), block.timestamp);
        vm.stopPrank();
    }

    function testDeposit() public {
        hoax(owner, 2000 ether);
        dps.addStake{value: 1000 ether}(IDividendsPairStaking.Faction.FROG, 0);
        dps.addStake{value: 1000 ether}(IDividendsPairStaking.Faction.DOG, 0);

        vm.prank(owner);
        uint256 bal = 1000 ether;
        mucus.transfer(address(2), bal);

        vm.prank(owner);
        mucus.transfer(address(mucus), swapTokensAtAmount);

        uint256 amountIn = 100 ether;
        address[] memory path = new address[](2);
        path[0] = address(mucus);
        path[1] = address(weth);

        uint256 tokensForStakers = swapTokensAtAmount * stakerFee / totalFee;
        uint256 totalFrogFactionAmount = dps.totalFrogFactionAmount();
        uint256 totalDogFactionAmount = dps.totalDogFactionAmount();
        uint256 totalStakedAmount = dps.totalStakedAmount();
        uint256 dividendsPerFrog =
            (tokensForStakers * totalDogFactionAmount / totalStakedAmount) / totalFrogFactionAmount;
        uint256 dividendsPerDog =
            (tokensForStakers - (tokensForStakers * totalDogFactionAmount / totalStakedAmount)) / totalDogFactionAmount;

        vm.startPrank(address(2));
        mucus.approve(address(router), amountIn);

        vm.expectEmit(true, true, true, true);
        emit DividendsPerShareUpdated(dividendsPerFrog, dividendsPerDog);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountIn, 0, path, address(2), block.timestamp);
        vm.stopPrank();

        assertEq(dps.dividendsPerFrog(), dividendsPerFrog, "dividendsPerFrog");
        assertEq(dps.dividendsPerDog(), dividendsPerDog, "dividendsPerDog");
    }

    function testRewardsOnAddingStake() public {
        hoax(address(2), 2000 ether);
        dps.addStake{value: 1000 ether}(frog, 0);

        triggerSwapBack();

        (
            ,
            uint256 frogFactionAmount,
            uint256 dogFactionAmount,
            uint256 previousFrogDpsBefore,
            uint256 previousDogDpsBefore,
        ) = dps.stakers(address(2));

        uint256 frogRewards = (dps.dividendsPerFrog() - previousFrogDpsBefore) * frogFactionAmount;
        uint256 dogRewards = (dps.dividendsPerDog() - previousDogDpsBefore) * dogFactionAmount;
        uint256 totalRewards = frogRewards + dogRewards;

        vm.expectEmit(true, true, true, true);
        emit DividendsEarned(address(2), totalRewards);

        vm.prank(address(2));
        dps.addStake{value: 1000 ether}(frog, 0);

        (,,, uint256 previousFrogDpsAfter, uint256 previousDogDpsAfter,) = dps.stakers(address(2));

        assertEq(previousFrogDpsAfter, dps.dividendsPerFrog(), "adding stake previousDividendsPerFrog");
        assertEq(previousDogDpsAfter, dps.dividendsPerDog(), "adding stake previousDividendsPerDog");
        assertEq(mucus.balanceOf(address(2)), totalRewards, "adding stake mucus balance of staker");
    }

    function testRewardsOnPartiallyRemovingStake() public {
        hoax(address(2), 2000 ether);
        dps.addStake{value: 1000 ether}(frog, 0);

        triggerSwapBack();

        (
            ,
            uint256 frogFactionAmount,
            uint256 dogFactionAmount,
            uint256 previousFrogDpsBefore,
            uint256 previousDogDpsBefore,
        ) = dps.stakers(address(2));

        uint256 liquidity = frogFactionAmount >> 1;
        uint256 frogRewards = (dps.dividendsPerFrog() - previousFrogDpsBefore) * frogFactionAmount;
        uint256 dogRewards = (dps.dividendsPerDog() - previousDogDpsBefore) * dogFactionAmount;
        uint256 totalRewards = frogRewards + dogRewards;
        (uint256 mucusRecieved,) =
            UniswapV2Library.removeLiquidityAmounts(address(pair), address(mucus), address(weth), liquidity);

        vm.expectEmit(true, true, true, true);
        emit DividendsEarned(address(2), totalRewards);

        vm.prank(address(2));
        vm.warp(block.timestamp + 2 weeks + 1);
        dps.removeStake(liquidity, frog);

        (,,, uint256 previousFrogDpsAfter, uint256 previousDogDpsAfter,) = dps.stakers(address(2));

        assertEq(previousFrogDpsAfter, dps.dividendsPerFrog(), "partially remove previousDividendsPerFrog");
        assertEq(previousDogDpsAfter, dps.dividendsPerDog(), "partially remove previousDividendsPerDog");
        assertEq(mucus.balanceOf(address(2)), totalRewards + mucusRecieved, "partially remove mucus balance of staker");
    }

    function testRewardsOnFullyRemovingStake() public {
        hoax(address(2), 2000 ether);
        dps.addStake{value: 1000 ether}(frog, 0);

        triggerSwapBack();

        (
            ,
            uint256 frogFactionAmount,
            uint256 dogFactionAmount,
            uint256 previousFrogDpsBefore,
            uint256 previousDogDpsBefore,
        ) = dps.stakers(address(2));

        uint256 frogRewards = (dps.dividendsPerFrog() - previousFrogDpsBefore) * frogFactionAmount;
        uint256 dogRewards = (dps.dividendsPerDog() - previousDogDpsBefore) * dogFactionAmount;
        uint256 totalRewards = frogRewards + dogRewards;
        (uint256 mucusRecieved,) =
            UniswapV2Library.removeLiquidityAmounts(address(pair), address(mucus), address(weth), frogFactionAmount);

        vm.expectEmit(true, true, true, true);
        emit DividendsEarned(address(2), totalRewards);

        vm.prank(address(2));
        vm.warp(block.timestamp + 2 weeks + 1);
        dps.removeStake(frogFactionAmount, frog);

        (,,, uint256 previousFrogDpsAfter, uint256 previousDogDpsAfter,) = dps.stakers(address(2));

        assertEq(previousFrogDpsAfter, 0, "fully remove previousDividendsPerFrog");
        assertEq(previousDogDpsAfter, 0, "fully remove previousDividendsPerDog");
        assertEq(mucus.balanceOf(address(2)), totalRewards + mucusRecieved, "fully remove mucus balance of staker");
    }

    function testRewardsOnVote() public {
        hoax(address(2), 2000 ether);
        dps.addStake{value: 1000 ether}(frog, 0);

        triggerSwapBack();

        (
            ,
            uint256 frogFactionAmount,
            uint256 dogFactionAmount,
            uint256 previousFrogDpsBefore,
            uint256 previousDogDpsBefore,
        ) = dps.stakers(address(2));

        uint256 frogRewards = (dps.dividendsPerFrog() - previousFrogDpsBefore) * frogFactionAmount;
        uint256 dogRewards = (dps.dividendsPerDog() - previousDogDpsBefore) * dogFactionAmount;
        uint256 totalRewards = frogRewards + dogRewards;

        vm.expectEmit(true, true, true, true);
        emit DividendsEarned(address(2), totalRewards);

        vm.prank(address(2));
        dps.vote(frogFactionAmount, dog);

        (,,, uint256 previousFrogDpsAfter, uint256 previousDogDpsAfter,) = dps.stakers(address(2));

        assertEq(previousFrogDpsAfter, dps.dividendsPerFrog(), "vote previousDividendsPerFrog");
        assertEq(previousDogDpsAfter, dps.dividendsPerDog(), "vote previousDividendsPerDog");
        assertEq(mucus.balanceOf(address(2)), totalRewards, "vote mucus balance of staker");
    }

    function testRewardsOnClaim() public {
        vm.prank(address(2));
        vm.expectRevert(bytes("Cannot claim if you haven't staked"));
        dps.claim();

        hoax(address(2), 1000 ether);
        dps.addStake{value: 1000 ether}(frog, 0);

        triggerSwapBack();

        (
            ,
            uint256 frogFactionAmount,
            uint256 dogFactionAmount,
            uint256 previousFrogDpsBefore,
            uint256 previousDogDpsBefore,
        ) = dps.stakers(address(2));

        uint256 frogRewards = (dps.dividendsPerFrog() - previousFrogDpsBefore) * frogFactionAmount;
        uint256 dogRewards = (dps.dividendsPerDog() - previousDogDpsBefore) * dogFactionAmount;
        uint256 totalRewards = frogRewards + dogRewards;

        vm.expectEmit(true, true, true, true);
        emit DividendsEarned(address(2), totalRewards);

        vm.prank(address(2));
        dps.claim();

        (,,, uint256 previousFrogDpsAfter, uint256 previousDogDpsAfter,) = dps.stakers(address(2));

        assertEq(previousFrogDpsAfter, dps.dividendsPerFrog(), "claim previousDividendsPerFrog");
        assertEq(previousDogDpsAfter, dps.dividendsPerDog(), "claim previousDividendsPerDog");
        assertEq(mucus.balanceOf(address(2)), totalRewards, "claim mucus balance of staker");
    }
}

contract DpsCycleSoup is Initial {
    function buyMucus() public {
        uint256 bal = 1000 ether;
        hoax(address(2), bal);
        uint256 amountOut = 100 ether;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(mucus);
        router.swapETHForExactTokens{value: bal}(amountOut, path, address(2), block.timestamp);
    }

    function testCycleFrogWin() public {
        hoax(address(2), 1000 ether);
        dps.addStake{value: 1000 ether}(frog, 0);

        vm.expectCall(address(dps), abi.encodeCall(IDividendsPairStaking.cycleSoup, ()), 2);
        buyMucus();

        vm.expectRevert(bytes("Cannot update soup cycle until the current cycle is over"));
        vm.prank(owner);
        dps.cycleSoup();

        vm.warp(block.timestamp + dps.soupCycleDuration());
        buyMucus();

        uint256 currentSoupIndex = dps.currentSoupIndex();
        (uint256 timestamp, IDividendsPairStaking.Faction soupedUp, uint256 totalFrogWins) =
            dps.soupCycles(currentSoupIndex);
        assertEq(currentSoupIndex, 1, "currentSoupIndex");
        assertEq(timestamp, block.timestamp, "timestamp");
        assertEq(uint256(soupedUp), uint256(frog), "soupedUp");
        assertEq(totalFrogWins, 2, "totalFrogWins");
    }

    function testCycleDogWin() public {
        hoax(address(2), 1000 ether);
        dps.addStake{value: 1000 ether}(dog, 0);

        vm.warp(block.timestamp + dps.soupCycleDuration());
        buyMucus();

        uint256 currentSoupIndex = dps.currentSoupIndex();
        (uint256 timestamp, IDividendsPairStaking.Faction soupedUp, uint256 totalFrogWins) =
            dps.soupCycles(currentSoupIndex);
        assertEq(currentSoupIndex, 1, "currentSoupIndex");
        assertEq(timestamp, block.timestamp, "timestamp");
        assertEq(uint256(soupedUp), uint256(dog), "soupedUp");
        assertEq(totalFrogWins, 1, "totalFrogWins");
    }
}

contract DpsOnlyOwner is Initial {
    event SoupCycleDurationUpdated(uint256 soupCycleDuration);

    function testCycleSoup() public {
        hoax(address(2), 1000 ether);
        dps.addStake{value: 1000 ether}(frog, 0);

        vm.warp(block.timestamp + dps.soupCycleDuration());

        vm.prank(address(2));
        vm.expectRevert();
        dps.cycleSoup();

        vm.prank(owner);
        dps.cycleSoup();
    }

    function testDeposit() public {
        vm.prank(address(2));
        vm.expectRevert();
        dps.deposit(100 ether);

        vm.prank(owner);
        dps.deposit(100 ether);
    }

    function testSetSoupCycleDuration() public {
        vm.prank(address(2));
        vm.expectRevert();
        dps.setSoupCycleDuration(1 weeks);

        vm.prank(owner);

        vm.expectEmit(true, true, true, true);
        emit SoupCycleDurationUpdated(1 weeks);

        dps.setSoupCycleDuration(1 weeks);

        assertEq(dps.soupCycleDuration(), 1 weeks, "soupCycleDuration");
    }

    function testWithdraw() public {
        vm.prank(owner);
        mucus.transfer(address(dps), 200 ether);
        hoax(owner, 200 ether);
        payable(dps).transfer(owner.balance);

        vm.prank(address(2));
        vm.expectRevert();
        dps.withdrawMucus();

        vm.prank(address(2));
        vm.expectRevert();
        dps.withdrawEth();

        vm.prank(owner);
        dps.withdrawMucus();

        vm.prank(owner);
        dps.withdrawEth();
    }
}

contract DpsViewFunctions is Initial {
    function testGetSoup() public {
        (
            uint256 currentSoupIndex,
            uint256 soupCycleDuration,
            IDividendsPairStaking.SoupCycle memory previousSoupCycle,
            IDividendsPairStaking.SoupCycle memory currentSoupCycle
        ) = dps.getSoup(2);

        (uint256 timestamp,,) = dps.soupCycles(0);

        assertEq(currentSoupIndex, dps.currentSoupIndex(), "currentSoupIndex");
        assertEq(soupCycleDuration, dps.soupCycleDuration(), "soupCycleDuration");
        assertEq(previousSoupCycle.timestamp, 0, "previousSoupCycle timestamp");
        assertEq(uint256(previousSoupCycle.soupedUp), uint256(dog), "previousSoupCycle soupedUp");
        assertEq(previousSoupCycle.totalFrogWins, 0, "previousSoupCycle totalFrogWins");
        assertEq(currentSoupCycle.timestamp, timestamp, "currentSoupCycle timestamp");
        assertEq(uint256(currentSoupCycle.soupedUp), uint256(frog), "currentSoupCycle soupedUp");
        assertEq(currentSoupCycle.totalFrogWins, 1, "currentSoupCycle totalFrogWins");
    }

    function testNextSoupCycle() public {
        uint256 nextSoupCycle = dps.nextSoupCycle();
        assertEq(nextSoupCycle, block.timestamp + dps.soupCycleDuration(), "nextSoupCycle");
    }

    function testSoupedUp() public {
        IDividendsPairStaking.Faction soupedUp = dps.getSoupedUp();
        assertEq(uint256(soupedUp), uint256(frog), "soupedUp");
    }
}
