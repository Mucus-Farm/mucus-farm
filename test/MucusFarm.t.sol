pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import {Mucus} from "../src/Mucus.sol";
import {DividendsPairStaking} from "../src/DividendsPairStaking.sol";
import {FrogsAndDogs} from "../src/FrogsAndDogs.sol";
import {IFrogsAndDogs} from "../src/interfaces/IFrogsAndDogs.sol";
import {MucusFarm} from "../src/MucusFarm.sol";
import {VRFCoordinatorV2Mock} from "./mocks/VRFCoordinatorV2Mock.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// uniswap
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";
import {UniswapV2Library} from "./lib/UniswapV2Library.sol";

contract Initial is Test {
    uint256 public constant ETH_MINT_PRICE = 0.03131 ether;
    uint256 public constant WINNING_POOL_TAX_RATE = 5;
    uint256 public constant LOSING_POOL_TAX_RATE = 20;
    uint256 public constant DAILY_MUCUS_RATE = 10000 * 1e18;
    uint256 public constant MAX_MUCUS_MINTED = 6262 * 1e8 * 1e18;
    address public _DEAD = 0x000000000000000000000000000000000000dEaD;

    uint256 public tokensPaidInEth = 2000; // 1/3 of the supply

    Mucus public mucus;
    DividendsPairStaking public dps;
    FrogsAndDogs public fnd;
    MucusFarm public mucusFarm;

    IUniswapV2Router02 public router;
    IUniswapV2Pair public pair;
    IERC20 public weth;
    VRFCoordinatorV2Mock public vrfCoordinator;

    IFrogsAndDogs.Faction frog = IFrogsAndDogs.Faction.FROG;
    IFrogsAndDogs.Faction dog = IFrogsAndDogs.Faction.DOG;

    address public teamWallet = address(123);
    address public owner = address(1);

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 16183456);
        vm.startPrank(owner);

        uint96 _baseFee = 100000000000000000;
        uint96 _gasPriceLink = 1000000000;
        vrfCoordinator = new VRFCoordinatorV2Mock(_baseFee, _gasPriceLink);

        uint64 _subscriptionId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(_subscriptionId, 1000 ether);

        address _uniswapRouter02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        mucus = new Mucus(teamWallet);
        dps = new DividendsPairStaking(address(mucus));
        fnd = new FrogsAndDogs(_subscriptionId, "", "", address(vrfCoordinator), address(mucus), address(dps));
        mucusFarm = new MucusFarm(address(fnd), address(mucus), address(dps));

        mucus.setDividendsPairStaking(address(dps));
        mucus.setMucusFarm(address(mucusFarm));
        mucus.setFrogsAndDogs(address(fnd));

        fnd.setMucusFarm(address(mucusFarm));

        vrfCoordinator.addConsumer(_subscriptionId, address(fnd));

        vm.stopPrank();
    }

    function mintEthSale() public {
        vm.deal(address(2), 1000 ether);
        vm.startPrank(address(2));
        for (uint256 i; i < tokensPaidInEth / 10; i++) {
            fnd.mint{value: ETH_MINT_PRICE * 10}(10, false);
        }
        vm.stopPrank();
    }

    function transformMultipleDogs(uint256 limit) public {
        vm.startPrank(address(2));
        uint256 requestId = vrfCoordinator.s_nextRequestId();
        uint256 j;

        // transform dogs
        for (uint256 i; i + 6 < limit; i += 6) {
            uint256[] memory tokenIds = new uint256[](3);
            tokenIds[0] = i;
            tokenIds[1] = i + 2;
            tokenIds[2] = i + 4;
            fnd.transform(tokenIds, dog, false);

            vrfCoordinator.fulfillRandomWords(requestId + j, address(fnd));
            j++;
        }
        vm.stopPrank();
    }

    function transformMultipleFrogs(uint256 limit) public {
        vm.startPrank(address(2));
        uint256 requestId = vrfCoordinator.s_nextRequestId();
        uint256 j;

        // transform frogs
        for (uint256 i = 1; i + 6 < limit; i += 6) {
            uint256[] memory tokenIds = new uint256[](3);
            tokenIds[0] = i;
            tokenIds[1] = i + 2;
            tokenIds[2] = i + 4;
            fnd.transform(tokenIds, frog, false);

            vrfCoordinator.fulfillRandomWords(requestId + j, address(fnd));
            j++;
        }

        vm.stopPrank();
    }

    function stakeGigas() internal returns (uint256[] memory) {
        transformMultipleFrogs(100);

        // the first 6000 to 6021 tokenIds were minted successfully
        uint256[] memory gigaTokenIds = new uint256[](10);
        for (uint256 i = 1; i < 20; i += 2) {
            gigaTokenIds[i] = 6000 + i;
        }

        vm.prank(address(2));
        mucusFarm.addManyToMucusFarm(address(2), gigaTokenIds);

        return gigaTokenIds;
    }

    function stakeChads() internal returns (uint256[] memory) {
        transformMultipleDogs(100);

        // the first 6000 to 6021 tokenIds were minted successfully
        uint256[] memory chadTokenIds = new uint256[](10);
        for (uint256 i; i < 20; i += 2) {
            chadTokenIds[i] = 6000 + i;
        }

        vm.prank(address(2));
        mucusFarm.addManyToMucusFarm(address(2), chadTokenIds);

        return chadTokenIds;
    }

    function parseEther(uint256 amount) public pure returns (uint256) {
        return amount / 1 ether;
    }
}

contract MucusFarmAddManyToFarm is Initial {
    event TokensStaked(address indexed parent, uint256[] tokenIds);

    function test_revertsAddManyToMucusFarm() public {
        mintEthSale();

        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i; i < 10; i++) {
            tokenIds[i] = i;
        }

        vm.expectRevert(bytes("sender must be the parent or the frogs and dogs contract"));
        vm.prank(address(2));
        mucusFarm.addManyToMucusFarm(address(1), tokenIds);
    }

    function test_addFrogsAndDogsMucusFarm() public {
        mintEthSale();

        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i; i < 10; i++) {
            tokenIds[i] = i;
        }

        vm.expectEmit(true, true, true, true);

        emit TokensStaked(address(2), tokenIds);

        vm.prank(address(2));
        mucusFarm.addManyToMucusFarm(address(2), tokenIds);

        for (uint256 i; i < 10; i++) {
            (
                address stakeOwner,
                uint256 lockingEndTime,
                uint256 previousClaimTimestamp,
                uint256 previousTaxPer,
                uint256 previousSoupIndex,
                uint256 gigaOrChadIndex
            ) = mucusFarm.farm(i);

            assertEq(stakeOwner, address(2), "owner");
            assertEq(lockingEndTime, block.timestamp + 3 days, "lockingEndTime");
            assertEq(previousClaimTimestamp, block.timestamp, "previousClaimTimestamp");
            assertEq(previousTaxPer, i % 2 == 0 ? mucusFarm.taxPerChad() : mucusFarm.taxPerGiga(), "previousTaxPer");
            assertEq(previousSoupIndex, dps.currentSoupIndex(), "previousSoupIndex");
            assertEq(gigaOrChadIndex, 0, "gigaOrChadIndex");
        }
    }

    function test_addGigasAndChadsToMucusFarm() public {
        mintEthSale();

        vm.prank(owner);
        mucus.transfer(address(2), 8000 * 1e8 * 1e18);

        transformMultipleDogs(100);
        transformMultipleFrogs(100);

        // the first 6000 to 6021 tokenIds were minted successfully
        uint256[] memory chadTokenIds = new uint256[](10);
        uint256[] memory gigaTokenIds = new uint256[](10);
        for (uint256 i; i < 20; i++) {
            if (i % 2 == 0) {
                chadTokenIds[i / 2] = i + 6000;
            } else {
                gigaTokenIds[i / 2] = i + 6000;
            }
        }

        vm.expectEmit(true, true, true, true);

        emit TokensStaked(address(2), chadTokenIds);

        vm.prank(address(2));
        mucusFarm.addManyToMucusFarm(address(2), chadTokenIds);

        for (uint256 i; i < chadTokenIds.length; i++) {
            (
                address stakeOwner,
                uint256 lockingEndTime,
                uint256 previousClaimTimestamp,
                uint256 previousTaxPer,
                uint256 previousSoupIndex,
                uint256 gigaOrChadIndex
            ) = mucusFarm.farm(chadTokenIds[i]);

            assertEq(stakeOwner, address(2), "owner");
            assertEq(lockingEndTime, block.timestamp + 3 days, "lockingEndTime");
            assertEq(previousClaimTimestamp, block.timestamp, "previousClaimTimestamp");
            assertEq(previousTaxPer, i % 2 == 0 ? mucusFarm.taxPerChad() : mucusFarm.taxPerGiga(), "previousTaxPer");
            assertEq(previousSoupIndex, dps.currentSoupIndex(), "previousSoupIndex");
            assertEq(gigaOrChadIndex, i, "gigaOrChadIndex");
        }

        vm.expectEmit(true, true, true, true);

        emit TokensStaked(address(2), gigaTokenIds);

        vm.prank(address(2));
        mucusFarm.addManyToMucusFarm(address(2), gigaTokenIds);

        for (uint256 i; i < gigaTokenIds.length; i++) {
            (
                address stakeOwner,
                uint256 lockingEndTime,
                uint256 previousClaimTimestamp,
                uint256 previousTaxPer,
                uint256 previousSoupIndex,
                uint256 gigaOrChadIndex
            ) = mucusFarm.farm(gigaTokenIds[i]);

            assertEq(stakeOwner, address(2), "owner");
            assertEq(lockingEndTime, block.timestamp + 3 days, "lockingEndTime");
            assertEq(previousClaimTimestamp, block.timestamp, "previousClaimTimestamp");
            assertEq(previousTaxPer, i % 2 == 0 ? mucusFarm.taxPerChad() : mucusFarm.taxPerGiga(), "previousTaxPer");
            assertEq(previousSoupIndex, dps.currentSoupIndex(), "previousSoupIndex");
            assertEq(gigaOrChadIndex, i, "gigaOrChadIndex");
        }
    }
}

contract MucusFarmStakeAndUnstake is Initial {
    event TokensStaked(address indexed parent, uint256[] tokenIds);
    event TokensUnstaked(address indexed parent, uint256[] tokenIds);

    function setUp() public override {
        super.setUp();

        mintEthSale();
    }

    function test_stakeAndUnstakeFnd() public {
        vm.startPrank(address(2));

        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i; i < 10; i++) {
            tokenIds[i] = i;
        }

        vm.expectEmit(true, true, true, true);
        emit TokensStaked(address(2), tokenIds);
        mucusFarm.addManyToMucusFarm(address(2), tokenIds);

        for (uint256 i; i < 10; i++) {
            assertEq(fnd.ownerOf(i), address(mucusFarm), "staked fnd");
        }

        vm.expectRevert(bytes("Cannot unstake frogs or dogs that are still locked"));
        mucusFarm.claimMany(tokenIds, true);

        vm.warp(block.timestamp + 3 days);
        vm.expectEmit(true, true, true, true);
        emit TokensUnstaked(address(2), tokenIds);
        mucusFarm.claimMany(tokenIds, true);

        for (uint256 i; i < 10; i++) {
            assertEq(fnd.ownerOf(i), address(2), "unstake fnd");
        }
    }
}

contract MucusFarmFndEarnings is Initial {
    event TokensFarmed(address indexed parent, uint256 mucusFarmed, uint256[] tokenIds);

    function setUp() public override {
        super.setUp();

        mintEthSale();
    }

    function test_revertsClaimMany() public {
        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i; i < 10; i++) {
            tokenIds[i] = i;
        }

        vm.startPrank(address(2));
        vm.expectRevert(bytes("Cannot claim rewards for frog or dog that you didn't stake"));
        mucusFarm.claimMany(tokenIds, false);

        mucusFarm.addManyToMucusFarm(address(2), tokenIds);

        vm.expectRevert(bytes("Cannot unstake frogs or dogs that are still locked"));
        mucusFarm.claimMany(tokenIds, true);
        vm.stopPrank();
    }

    function test_stakeThenClaim() public {
        vm.startPrank(address(2));
        uint256[] memory tokenIds = new uint256[](2);
        for (uint256 i; i < 2; i++) {
            tokenIds[i] = i;
        }

        uint256 previousBlockTimestamp = block.timestamp;
        uint256 dailyMucusFarmed = DAILY_MUCUS_RATE * 2;
        uint256 dailyClaimedTax = DAILY_MUCUS_RATE * 20 / 100;
        uint256 dailyBurnedTax = DAILY_MUCUS_RATE * 5 / 100;

        mucusFarm.addManyToMucusFarm(address(2), tokenIds);
        vm.warp(previousBlockTimestamp + 1 days);

        vm.expectEmit(true, true, true, true);
        emit TokensFarmed(address(2), dailyMucusFarmed - dailyClaimedTax - dailyBurnedTax, tokenIds);
        mucusFarm.claimMany(tokenIds, false);
        vm.stopPrank();

        assertEq(mucus.balanceOf(address(2)), dailyMucusFarmed - dailyClaimedTax - dailyBurnedTax, "mucus balance");
        assertEq(mucus.balanceOf(_DEAD), dailyBurnedTax, "burned tax");
        assertEq(mucusFarm.totalMucusMinted(), dailyMucusFarmed - dailyClaimedTax, "totalMucusMinted");

        for (uint256 i; i < 2; i++) {
            (,, uint256 previousClaimTimestamp,, uint256 previousSoupIndex,) = mucusFarm.farm(i);

            assertEq(previousClaimTimestamp, previousBlockTimestamp + 1 days, "previousClaimTimestamp");
            assertEq(previousSoupIndex, dps.currentSoupIndex(), "previousSoupIndex");
        }
    }

    function test_doubleStakeThenClaim() public {
        uint256[] memory tokenIds = new uint256[](4);
        uint256[] memory tokenIdsSet1 = new uint256[](2);
        uint256[] memory tokenIdsSet2 = new uint256[](2);
        for (uint256 i; i < 4; i++) {
            tokenIds[i] = i;
            if (i < 2) tokenIdsSet1[i] = i;
            else tokenIdsSet2[i - 2] = i;
        }

        uint256 previousBlockTimestamp = block.timestamp;

        vm.startPrank(address(2));
        mucusFarm.addManyToMucusFarm(address(2), tokenIdsSet1);
        vm.warp(previousBlockTimestamp + 1 days);
        mucusFarm.addManyToMucusFarm(address(2), tokenIdsSet2);
        vm.warp(previousBlockTimestamp + 2 days);
        mucusFarm.claimMany(tokenIds, false);
        vm.stopPrank();

        uint256 dailyMucusFarmed = DAILY_MUCUS_RATE * 2;
        uint256 dailyClaimedTax = DAILY_MUCUS_RATE * 20 / 100;
        uint256 dailyBurnedTax = DAILY_MUCUS_RATE * 5 / 100;

        assertEq(
            mucus.balanceOf(address(2)), (dailyMucusFarmed - dailyClaimedTax - dailyBurnedTax) * 3, "mucus balance"
        );
        assertEq(mucus.balanceOf(_DEAD), dailyBurnedTax * 3, "burned tax");
        assertEq(mucusFarm.totalMucusMinted(), (dailyMucusFarmed - dailyClaimedTax) * 3, "totalMucusMinted");

        for (uint256 i; i < 4; i++) {
            (,, uint256 previousClaimTimestamp,, uint256 previousSoupIndex,) = mucusFarm.farm(i);

            assertEq(previousClaimTimestamp, previousBlockTimestamp + 2 days, "previousClaimTimestamp");
            assertEq(previousSoupIndex, dps.currentSoupIndex(), "previousSoupIndex");
        }
    }

    function test_stakeThenDoubleClaim() public {
        uint256[] memory tokenIds = new uint256[](2);
        for (uint256 i; i < 2; i++) {
            tokenIds[i] = i;
        }

        uint256 previousBlockTimestamp = block.timestamp;

        vm.startPrank(address(2));
        mucusFarm.addManyToMucusFarm(address(2), tokenIds);
        vm.warp(previousBlockTimestamp + 1 days);
        mucusFarm.claimMany(tokenIds, false);
        vm.warp(previousBlockTimestamp + 2 days);
        mucusFarm.claimMany(tokenIds, false);
        vm.stopPrank();

        uint256 dailyMucusFarmed = DAILY_MUCUS_RATE * 2;
        uint256 dailyClaimedTax = DAILY_MUCUS_RATE * 20 / 100;
        uint256 dailyBurnedTax = DAILY_MUCUS_RATE * 5 / 100;

        assertEq(
            mucus.balanceOf(address(2)), (dailyMucusFarmed - dailyClaimedTax - dailyBurnedTax) * 2, "mucus balance"
        );
        assertEq(mucus.balanceOf(_DEAD), dailyBurnedTax * 2, "burned tax");
        assertEq(mucusFarm.totalMucusMinted(), (dailyMucusFarmed - dailyClaimedTax) * 2, "totalMucusMinted");

        for (uint256 i; i < 2; i++) {
            (,, uint256 previousClaimTimestamp,, uint256 previousSoupIndex,) = mucusFarm.farm(i);

            assertEq(previousClaimTimestamp, previousBlockTimestamp + 2 days, "previousClaimTimestamp");
            assertEq(previousSoupIndex, dps.currentSoupIndex(), "previousSoupIndex");
        }
    }

    function test_doubleStakeThenDoubleClaim() public {
        uint256[] memory tokenIds = new uint256[](4);
        uint256[] memory tokenIdsSet1 = new uint256[](2);
        uint256[] memory tokenIdsSet2 = new uint256[](2);
        for (uint256 i; i < 4; i++) {
            tokenIds[i] = i;
            if (i < 2) tokenIdsSet1[i] = i;
            else tokenIdsSet2[i - 2] = i;
        }

        uint256 previousBlockTimestamp = block.timestamp;

        vm.startPrank(address(2));
        mucusFarm.addManyToMucusFarm(address(2), tokenIdsSet1);
        vm.warp(previousBlockTimestamp + 1 days);
        mucusFarm.addManyToMucusFarm(address(2), tokenIdsSet2);
        vm.warp(previousBlockTimestamp + 2 days);
        mucusFarm.claimMany(tokenIds, false);
        vm.warp(previousBlockTimestamp + 3 days);
        mucusFarm.claimMany(tokenIds, false);
        vm.stopPrank();

        uint256 dailyMucusFarmed = DAILY_MUCUS_RATE * 2;
        uint256 dailyClaimedTax = DAILY_MUCUS_RATE * 20 / 100;
        uint256 dailyBurnedTax = DAILY_MUCUS_RATE * 5 / 100;

        assertEq(
            mucus.balanceOf(address(2)), (dailyMucusFarmed - dailyClaimedTax - dailyBurnedTax) * 5, "mucus balance"
        );
        assertEq(mucus.balanceOf(_DEAD), dailyBurnedTax * 5, "burned tax");
        assertEq(mucusFarm.totalMucusMinted(), (dailyMucusFarmed - dailyClaimedTax) * 5, "totalMucusMinted");

        for (uint256 i; i < 4; i++) {
            (,, uint256 previousClaimTimestamp,, uint256 previousSoupIndex,) = mucusFarm.farm(i);

            assertEq(previousClaimTimestamp, previousBlockTimestamp + 3 days, "previousClaimTimestamp");
            assertEq(previousSoupIndex, dps.currentSoupIndex(), "previousSoupIndex");
        }
    }
}

contract MucusFarmGcEarnings is Initial {
    uint256 public dailyMucusFarmed = DAILY_MUCUS_RATE * 2 * 3;
    uint256 public dailyClaimedTax = DAILY_MUCUS_RATE * 3 * 20 / 100;
    uint256 public dailyBurnedTax = DAILY_MUCUS_RATE * 3 * 5 / 100;

    function setUp() public override {
        super.setUp();

        mintEthSale();

        vm.prank(owner);
        mucus.transfer(address(2), 9393 ether * 32);

        transformMultipleDogs(100);
        transformMultipleFrogs(100);

        console.log("mucus balance: ", parseEther(mucus.balanceOf(address(2))));
    }

    function test_stakeThenClaim() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 6000;
        tokenIds[1] = 6001;

        uint256 previousTimestamp = block.timestamp;

        vm.startPrank(address(2));
        mucusFarm.addManyToMucusFarm(address(2), tokenIds);
        vm.warp(previousTimestamp + 1 days);
        mucusFarm.claimMany(tokenIds, false);

        console.log("daily mucus farmed: ", parseEther(dailyMucusFarmed));
        console.log("daily claimed tax: ", parseEther(dailyClaimedTax));
        console.log("daily burned tax: ", parseEther(dailyBurnedTax));

        assertEq(mucus.balanceOf(address(2)), dailyMucusFarmed - dailyClaimedTax - dailyBurnedTax, "balance of user");
        assertEq(mucusFarm.taxPerChad(), 0, "taxPerChad");
        assertEq(mucusFarm.taxPerGiga(), dailyClaimedTax, "taxPerGiga");
        assertEq(mucusFarm.unclaimedChadTax(), 0, "unclaimedChadTax");
        assertEq(mucusFarm.unclaimedGigaTax(), 0, "unclaimedGigaTax");
    }
}

// test for this in gc earnings
