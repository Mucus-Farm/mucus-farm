pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import {Mucus} from "../src/Mucus.sol";
import {DividendsPairStaking} from "../src/DividendsPairStaking.sol";
import {IDividendsPairStaking} from "../src/interfaces/IDividendsPairStaking.sol";
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
    address public constant _DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant ethAmount = 100000000000 ether;
    uint256 public constant tokenAmount = 100000000000 ether;

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
        bytes32 _keyHash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;
        vrfCoordinator = new VRFCoordinatorV2Mock(_baseFee, _gasPriceLink);

        uint64 _subscriptionId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(_subscriptionId, 1000 ether);

        mucus = new Mucus(teamWallet);
        dps = new DividendsPairStaking(address(mucus));
        fnd =
        new FrogsAndDogs(ETH_MINT_PRICE, keccak256(abi.encode(address(0))), _subscriptionId, "", "", address(vrfCoordinator), _keyHash, address(mucus), address(dps));
        mucusFarm = new MucusFarm(address(fnd), address(mucus), address(dps));

        mucus.setDividendsPairStaking(address(dps));
        mucus.setMucusFarm(address(mucusFarm));
        mucus.setFrogsAndDogs(address(fnd));

        fnd.setMucusFarm(address(mucusFarm));
        fnd.setPublicMintStarted();

        vrfCoordinator.addConsumer(_subscriptionId, address(fnd));

        vm.stopPrank();
    }

    function addLiquidity() public {
        vm.startPrank(owner);
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
        vm.stopPrank();
    }

    function mintEthSale() public {
        vm.deal(address(2), 1000 ether);
        vm.startPrank(address(2));
        for (uint256 i; i < tokensPaidInEth / 10; i++) {
            fnd.mint{value: ETH_MINT_PRICE * 10}(10);
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
            fnd.transform(tokenIds, dog);

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
            fnd.transform(tokenIds, frog);

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
        mucusFarm.addManyToMucusFarm(gigaTokenIds);

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
        mucusFarm.addManyToMucusFarm(chadTokenIds);

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
        mucusFarm.addManyToMucusFarm(tokenIds);
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
        mucusFarm.addManyToMucusFarm(tokenIds);

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
        mucus.transfer(address(2), 3000 * 1e8 ether);

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
        mucusFarm.addManyToMucusFarm(chadTokenIds);

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
        mucusFarm.addManyToMucusFarm(gigaTokenIds);

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
        mucusFarm.addManyToMucusFarm(tokenIds);

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
            (
                address stakeOwner,
                uint256 lockingEndTime,
                uint256 previousClaimTimestamp,
                uint256 previousTaxPer,
                uint256 previousSoupIndex,
                uint256 gigaOrChadIndex
            ) = mucusFarm.farm(i);
            assertEq(stakeOwner, address(0), "stake owner");
            assertEq(lockingEndTime, 0, "lockingEndTime");
            assertEq(previousClaimTimestamp, 0, "previousClaimTimestamp");
            assertEq(previousTaxPer, 0, "previousTaxPer");
            assertEq(previousSoupIndex, 0, "previousSoupIndex");
            assertEq(gigaOrChadIndex, 0, "gigaOrChadIndex");
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

        mucusFarm.addManyToMucusFarm(tokenIds);

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

        mucusFarm.addManyToMucusFarm(tokenIds);
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
        mucusFarm.addManyToMucusFarm(tokenIdsSet1);
        vm.warp(previousBlockTimestamp + 1 days);
        mucusFarm.addManyToMucusFarm(tokenIdsSet2);
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
        mucusFarm.addManyToMucusFarm(tokenIds);
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
        mucusFarm.addManyToMucusFarm(tokenIdsSet1);
        vm.warp(previousBlockTimestamp + 1 days);
        mucusFarm.addManyToMucusFarm(tokenIdsSet2);
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

        vm.startPrank(address(2));
        fnd.transferFrom(address(2), address(3), 101);
        fnd.transferFrom(address(2), address(3), 102);
        vm.stopPrank();
    }

    function test_stakeThenClaim() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 6000;
        tokenIds[1] = 6001;

        vm.startPrank(address(2));
        mucusFarm.addManyToMucusFarm(tokenIds);
        vm.warp(block.timestamp + 1 days);
        mucusFarm.claimMany(tokenIds, false);

        assertEq(mucus.balanceOf(address(2)), dailyMucusFarmed - dailyClaimedTax - dailyBurnedTax, "balance of user");
        assertEq(mucusFarm.taxPerChad(), 0, "taxPerChad");
        assertEq(mucusFarm.taxPerGiga(), dailyClaimedTax, "taxPerGiga");
        assertEq(mucusFarm.unclaimedChadTax(), 0, "unclaimedChadTax");
        assertEq(mucusFarm.unclaimedGigaTax(), 0, "unclaimedGigaTax");
    }

    function test_fndStakeThenClaimThenGcStakeThenClaim() public {
        (, uint256 fndClaimedTax,) = fndStakeThenClaim();

        assertEq(mucusFarm.unclaimedGigaTax(), fndClaimedTax, "giga unclaimedTax");
        assertEq(mucusFarm.unclaimedChadTax(), 0, "chad unclaimedTax");
        assertEq(mucusFarm.taxPerGiga(), 0, "taxPerGiga prior");
        assertEq(mucusFarm.taxPerChad(), 0, "taxPerChad prior");

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 6000;
        tokenIds[1] = 6001;

        vm.startPrank(address(2));
        mucusFarm.addManyToMucusFarm(tokenIds);
        vm.warp(block.timestamp + 1 days);
        mucusFarm.claimMany(tokenIds, false);

        assertEq(mucus.balanceOf(address(2)), (dailyMucusFarmed - dailyClaimedTax - dailyBurnedTax), "balance of user");
        assertEq(mucusFarm.taxPerChad(), 0, "taxPerChad");
        assertEq(mucusFarm.taxPerGiga(), dailyClaimedTax + fndClaimedTax, "taxPerGiga");
        assertEq(mucusFarm.unclaimedChadTax(), 0, "unclaimedChadTax");
        assertEq(mucusFarm.unclaimedGigaTax(), 0, "unclaimedGigaTax");
    }

    function test_fndStakeThenClaimThenGcStakeFndStakeClaimThenClaim() public {
        (, uint256 fndClaimedTax,) = fndStakeThenClaim();

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 6000;
        tokenIds[1] = 6001;

        vm.prank(address(2));
        mucusFarm.addManyToMucusFarm(tokenIds);
        fndClaim();
        vm.warp(block.timestamp + 1 days);
        vm.prank(address(2));
        mucusFarm.claimMany(tokenIds, false);

        assertEq(
            mucus.balanceOf(address(2)),
            dailyMucusFarmed - dailyClaimedTax - dailyBurnedTax + fndClaimedTax,
            "balance of user"
        );
        assertEq(mucusFarm.taxPerChad(), 0, "taxPerChad");
        assertEq(mucusFarm.taxPerGiga(), dailyClaimedTax + fndClaimedTax, "taxPerGiga");
        assertEq(mucusFarm.unclaimedChadTax(), 0, "unclaimedChadTax");
        assertEq(mucusFarm.unclaimedGigaTax(), 0, "unclaimedGigaTax");
    }

    function test_GcStakeThenFndStakeClaimThenClaim() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 6000;
        tokenIds[1] = 6001;

        vm.prank(address(2));
        mucusFarm.addManyToMucusFarm(tokenIds);

        (, uint256 fndClaimedTax,) = fndStakeThenClaim();
        assertEq(mucusFarm.taxPerChad(), 0, "taxPerChad");
        assertEq(mucusFarm.taxPerGiga(), fndClaimedTax, "taxPerGiga");
        assertEq(mucusFarm.unclaimedChadTax(), 0, "unclaimedChadTax");
        assertEq(mucusFarm.unclaimedGigaTax(), 0, "unclaimedGigaTax");

        vm.prank(address(2));
        mucusFarm.claimMany(tokenIds, false);

        assertEq(
            mucus.balanceOf(address(2)),
            dailyMucusFarmed - dailyClaimedTax - dailyBurnedTax + fndClaimedTax,
            "balance of user"
        );
        assertEq(mucusFarm.taxPerChad(), 0, "taxPerChad");
        assertEq(mucusFarm.taxPerGiga(), fndClaimedTax + dailyClaimedTax, "taxPerGiga");
        assertEq(mucusFarm.unclaimedChadTax(), 0, "unclaimedChadTax");
        assertEq(mucusFarm.unclaimedGigaTax(), 0, "unclaimedGigaTax");
    }

    function fndStakeThenClaim() public returns (uint256, uint256, uint256) {
        vm.startPrank(address(3));
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 101;
        tokenIds[1] = 102;

        uint256 fndMucusFarmed = DAILY_MUCUS_RATE * 2;
        uint256 fndClaimedTax = DAILY_MUCUS_RATE * 20 / 100;
        uint256 fndBurnedTax = DAILY_MUCUS_RATE * 5 / 100;

        mucusFarm.addManyToMucusFarm(tokenIds);
        vm.warp(block.timestamp + 1 days);
        mucusFarm.claimMany(tokenIds, false);
        vm.stopPrank();

        return (fndMucusFarmed, fndClaimedTax, fndBurnedTax);
    }

    function fndClaim() public returns (uint256, uint256, uint256) {
        vm.startPrank(address(3));
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 101;
        tokenIds[1] = 102;

        uint256 fndMucusFarmed = DAILY_MUCUS_RATE * 2;
        uint256 fndClaimedTax = DAILY_MUCUS_RATE * 20 / 100;
        uint256 fndBurnedTax = DAILY_MUCUS_RATE * 5 / 100;

        mucusFarm.claimMany(tokenIds, false);
        vm.stopPrank();

        return (fndMucusFarmed, fndClaimedTax, fndBurnedTax);
    }
}

contract MucusFarmSoupCycleEarnings is Initial {
    // grabbed this number from DpsVoting test contract
    uint256 totalVotes = 498499999999999999999;
    uint256 public dailyMucusFarmed = DAILY_MUCUS_RATE;
    uint256 public dailyClaimedTax = DAILY_MUCUS_RATE * 20 / 100;
    uint256 public dailyBurnedTax = DAILY_MUCUS_RATE * 5 / 100;

    function setUp() public override {
        super.setUp();

        address _uniswapRouter02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        router = IUniswapV2Router02(_uniswapRouter02);

        addLiquidity();

        mintEthSale();

        hoax(owner, 1000 ether);
        dps.addStake{value: 1000 ether}(IDividendsPairStaking.Faction.FROG, 0);
    }

    function test_3cyclePassFFDFDClaimFrog() public {
        // stake in the middle of a cycle
        uint256 previousSoupCycleTimestamp = block.timestamp;
        vm.warp(block.timestamp + 2 days);
        uint256 stakeTimestamp = block.timestamp;

        stakeFrog();
        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        dps.cycleSoup();

        // 3 cycle pass of FDF
        cycleDogWin();
        cycleFrogWin();
        cycleDogWin();

        uint256 currentSoupCycleTimestamp = block.timestamp;

        // claim in the middle of a cycle
        vm.warp(block.timestamp + 1 days);
        claimFrog();

        // assert earnings
        uint256 previousLeftoverEarnings =
            dailyMucusFarmed * (previousSoupCycleTimestamp + dps.soupCycleDuration() - stakeTimestamp) / 1 days;
        uint256 previousLeftoverBurnedTax =
            dailyBurnedTax * (previousSoupCycleTimestamp + dps.soupCycleDuration() - stakeTimestamp) / 1 days;
        uint256 previousProfit = previousLeftoverEarnings - previousLeftoverBurnedTax;

        // * 3 since one cycle is 3 days
        uint256 cycleEarnings = dailyMucusFarmed * 3 * 3;
        uint256 cycleClaimedTax = dailyClaimedTax * 3;
        uint256 cycleBurnTax = dailyBurnedTax * 3 * 2;
        uint256 cycleProfit = cycleEarnings - cycleClaimedTax - cycleBurnTax;

        uint256 currentLeftoverEarnings = dailyMucusFarmed * (block.timestamp - currentSoupCycleTimestamp) / 1 days;
        uint256 currentLeftoverClaimedTax = dailyClaimedTax * (block.timestamp - currentSoupCycleTimestamp) / 1 days;
        uint256 currentProfit = currentLeftoverEarnings - currentLeftoverClaimedTax;

        assertEq(mucus.balanceOf(address(2)), previousProfit + cycleProfit + currentProfit, "user balance");
        assertEq(mucus.balanceOf(_DEAD), previousLeftoverBurnedTax + cycleBurnTax, "burned tax");
        assertEq(mucusFarm.unclaimedChadTax(), cycleClaimedTax + currentLeftoverClaimedTax, "unclaimed chad tax");
        assertEq(mucusFarm.unclaimedGigaTax(), 0, "unclaimed giga tax");
        assertEq(mucusFarm.taxPerChad(), 0, "tax per chad");
        assertEq(mucusFarm.taxPerGiga(), 0, "tax per giga");
    }

    function test_3cyclePassFFDFDClaimDog() public {
        // stake in the middle of a cycle
        uint256 previousSoupCycleTimestamp = block.timestamp;
        vm.warp(block.timestamp + 2 days);
        uint256 stakeTimestamp = block.timestamp;

        stakeDog();
        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        dps.cycleSoup();

        // 3 cycle pass of FDF
        cycleDogWin();
        cycleFrogWin();
        cycleDogWin();

        uint256 currentSoupCycleTimestamp = block.timestamp;

        // claim in the middle of a cycle
        vm.warp(block.timestamp + 1 days);
        claimDog();

        // assert earnings
        uint256 previousLeftoverEarnings =
            dailyMucusFarmed * (previousSoupCycleTimestamp + dps.soupCycleDuration() - stakeTimestamp) / 1 days;
        uint256 previousLeftoverClaimedTax =
            dailyClaimedTax * (previousSoupCycleTimestamp + dps.soupCycleDuration() - stakeTimestamp) / 1 days;
        uint256 previousProfit = previousLeftoverEarnings - previousLeftoverClaimedTax;

        // * 3 since one cycle is 3 days
        uint256 cycleEarnings = dailyMucusFarmed * 3 * 3;
        uint256 cycleClaimedTax = dailyClaimedTax * 3 * 2;
        uint256 cycleBurnTax = dailyBurnedTax * 3;
        uint256 cycleProfit = cycleEarnings - cycleClaimedTax - cycleBurnTax;

        uint256 currentLeftoverEarnings = dailyMucusFarmed * (block.timestamp - currentSoupCycleTimestamp) / 1 days;
        uint256 currentLeftoverBurnTax = dailyBurnedTax * (block.timestamp - currentSoupCycleTimestamp) / 1 days;
        uint256 currentProfit = currentLeftoverEarnings - currentLeftoverBurnTax;

        assertEq(mucus.balanceOf(address(2)), previousProfit + cycleProfit + currentProfit, "user balance");
        assertEq(mucus.balanceOf(_DEAD), dailyBurnedTax + cycleBurnTax, "burned tax");
        assertEq(mucusFarm.unclaimedChadTax(), 0, "unclaimed chad tax");
        assertEq(mucusFarm.unclaimedGigaTax(), cycleClaimedTax + previousLeftoverClaimedTax, "unclaimed chad tax");
        assertEq(mucusFarm.taxPerChad(), 0, "tax per chad");
        assertEq(mucusFarm.taxPerGiga(), 0, "tax per giga");
    }

    function test_FFClaimFrog() public {
        // stake in the middle of a cycle
        uint256 previousSoupCycleTimestamp = block.timestamp;
        vm.warp(block.timestamp + 2 days);
        uint256 stakeTimestamp = block.timestamp;

        stakeFrog();
        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        dps.cycleSoup();

        uint256 currentSoupCycleTimestamp = block.timestamp;

        // claim in the middle of a cycle
        vm.warp(block.timestamp + 1 days);
        claimFrog();

        // assert earnings
        uint256 previousLeftoverEarnings =
            dailyMucusFarmed * (previousSoupCycleTimestamp + dps.soupCycleDuration() - stakeTimestamp) / 1 days;
        uint256 previousLeftoverBurnedTax =
            dailyBurnedTax * (previousSoupCycleTimestamp + dps.soupCycleDuration() - stakeTimestamp) / 1 days;
        uint256 previousProfit = previousLeftoverEarnings - previousLeftoverBurnedTax;

        uint256 currentLeftoverEarnings = dailyMucusFarmed * (block.timestamp - currentSoupCycleTimestamp) / 1 days;
        uint256 currentLeftoverBurnedTax = dailyBurnedTax * (block.timestamp - currentSoupCycleTimestamp) / 1 days;
        uint256 currentProfit = currentLeftoverEarnings - currentLeftoverBurnedTax;

        assertEq(mucus.balanceOf(address(2)), previousProfit + currentProfit, "user balance");
        assertEq(mucus.balanceOf(_DEAD), previousLeftoverBurnedTax + currentLeftoverBurnedTax, "burned tax");
        assertEq(mucusFarm.unclaimedChadTax(), 0, "unclaimed chad tax");
        assertEq(mucusFarm.unclaimedGigaTax(), 0, "unclaimed chad tax");
        assertEq(mucusFarm.taxPerChad(), 0, "tax per chad");
        assertEq(mucusFarm.taxPerGiga(), 0, "tax per giga");
    }

    function test_FFClaimDog() public {
        // stake in the middle of a cycle
        uint256 previousSoupCycleTimestamp = block.timestamp;
        vm.warp(block.timestamp + 2 days);
        uint256 stakeTimestamp = block.timestamp;

        stakeDog();
        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        dps.cycleSoup();

        uint256 currentSoupCycleTimestamp = block.timestamp;

        // claim in the middle of a cycle
        vm.warp(block.timestamp + 1 days);
        claimDog();

        // assert earnings
        uint256 previousLeftoverEarnings =
            dailyMucusFarmed * (previousSoupCycleTimestamp + dps.soupCycleDuration() - stakeTimestamp) / 1 days;
        uint256 previousLeftoverClaimedTax =
            dailyClaimedTax * (previousSoupCycleTimestamp + dps.soupCycleDuration() - stakeTimestamp) / 1 days;
        uint256 previousProfit = previousLeftoverEarnings - previousLeftoverClaimedTax;

        uint256 currentLeftoverEarnings = dailyMucusFarmed * (block.timestamp - currentSoupCycleTimestamp) / 1 days;
        uint256 currentLeftoverClaimedTax = dailyClaimedTax * (block.timestamp - currentSoupCycleTimestamp) / 1 days;
        uint256 currentProfit = currentLeftoverEarnings - currentLeftoverClaimedTax;

        assertEq(mucus.balanceOf(address(2)), previousProfit + currentProfit, "user balance");
        assertEq(mucus.balanceOf(_DEAD), 0, "burned tax");
        assertEq(mucusFarm.unclaimedChadTax(), 0, "unclaimed chad tax");
        assertEq(
            mucusFarm.unclaimedGigaTax(), previousLeftoverClaimedTax + currentLeftoverClaimedTax, "unclaimed chad tax"
        );
        assertEq(mucusFarm.taxPerChad(), 0, "tax per chad");
        assertEq(mucusFarm.taxPerGiga(), 0, "tax per giga");
    }

    function test_FDClaimFrog() public {
        // stake in the middle of a cycle
        uint256 previousSoupCycleTimestamp = block.timestamp;
        vm.warp(block.timestamp + 2 days);
        uint256 stakeTimestamp = block.timestamp;

        stakeFrog();
        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        dps.vote(totalVotes, IDividendsPairStaking.Faction.DOG);
        vm.prank(owner);
        dps.cycleSoup();

        uint256 currentSoupCycleTimestamp = block.timestamp;

        // claim in the middle of a cycle
        vm.warp(block.timestamp + 1 days);
        claimFrog();

        // assert earnings
        uint256 previousLeftoverEarnings =
            dailyMucusFarmed * (previousSoupCycleTimestamp + dps.soupCycleDuration() - stakeTimestamp) / 1 days;
        uint256 previousLeftoverBurnedTax =
            dailyBurnedTax * (previousSoupCycleTimestamp + dps.soupCycleDuration() - stakeTimestamp) / 1 days;
        uint256 previousProfit = previousLeftoverEarnings - previousLeftoverBurnedTax;

        uint256 currentLeftoverEarnings = dailyMucusFarmed * (block.timestamp - currentSoupCycleTimestamp) / 1 days;
        uint256 currentLeftoverClaimedTax = dailyClaimedTax * (block.timestamp - currentSoupCycleTimestamp) / 1 days;
        uint256 currentProfit = currentLeftoverEarnings - currentLeftoverClaimedTax;

        assertEq(mucus.balanceOf(address(2)), previousProfit + currentProfit, "user balance");
        assertEq(mucus.balanceOf(_DEAD), previousLeftoverBurnedTax, "burned tax");
        assertEq(mucusFarm.unclaimedChadTax(), currentLeftoverClaimedTax, "unclaimed chad tax");
        assertEq(mucusFarm.unclaimedGigaTax(), 0, "unclaimed chad tax");
        assertEq(mucusFarm.taxPerChad(), 0, "tax per chad");
        assertEq(mucusFarm.taxPerGiga(), 0, "tax per giga");
    }

    function test_FDClaimDog() public {
        // stake in the middle of a cycle
        uint256 previousSoupCycleTimestamp = block.timestamp;
        vm.warp(block.timestamp + 2 days);
        uint256 stakeTimestamp = block.timestamp;

        stakeDog();
        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        dps.vote(totalVotes, IDividendsPairStaking.Faction.DOG);
        vm.prank(owner);
        dps.cycleSoup();

        uint256 currentSoupCycleTimestamp = block.timestamp;

        // claim in the middle of a cycle
        vm.warp(block.timestamp + 1 days);
        claimDog();

        // assert earnings
        uint256 previousLeftoverEarnings =
            dailyMucusFarmed * (previousSoupCycleTimestamp + dps.soupCycleDuration() - stakeTimestamp) / 1 days;
        uint256 previousLeftoverClaimedTax =
            dailyClaimedTax * (previousSoupCycleTimestamp + dps.soupCycleDuration() - stakeTimestamp) / 1 days;
        uint256 previousProfit = previousLeftoverEarnings - previousLeftoverClaimedTax;

        uint256 currentLeftoverEarnings = dailyMucusFarmed * (block.timestamp - currentSoupCycleTimestamp) / 1 days;
        uint256 currentLeftoverBurnedTax = dailyBurnedTax * (block.timestamp - currentSoupCycleTimestamp) / 1 days;
        uint256 currentProfit = currentLeftoverEarnings - currentLeftoverBurnedTax;

        assertEq(mucus.balanceOf(address(2)), previousProfit + currentProfit, "user balance");
        assertEq(mucus.balanceOf(_DEAD), currentLeftoverBurnedTax, "burned tax");
        assertEq(mucusFarm.unclaimedChadTax(), 0, "unclaimed chad tax");
        assertEq(mucusFarm.unclaimedGigaTax(), previousLeftoverClaimedTax, "unclaimed chad tax");
        assertEq(mucusFarm.taxPerChad(), 0, "tax per chad");
        assertEq(mucusFarm.taxPerGiga(), 0, "tax per giga");
    }

    // uint256 i = dps.currentSoupIndex();
    // (uint256 timestamp, IDividendsPairStaking.Faction soupedUp, uint256 totalFrogWins) = dps.soupCycles(i);

    function stakeDog() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        vm.prank(address(2));
        mucusFarm.addManyToMucusFarm(tokenIds);
    }

    function claimDog() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;

        vm.prank(address(2));
        mucusFarm.claimMany(tokenIds, false);
    }

    function stakeFrog() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        vm.prank(address(2));
        mucusFarm.addManyToMucusFarm(tokenIds);
    }

    function claimFrog() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        vm.prank(address(2));
        mucusFarm.claimMany(tokenIds, false);
    }

    function cycleFrogWin() public {
        vm.startPrank(owner);
        vm.warp(block.timestamp + dps.soupCycleDuration());
        dps.vote(totalVotes, IDividendsPairStaking.Faction.FROG);
        dps.cycleSoup();
        vm.stopPrank();
    }

    function cycleDogWin() public {
        vm.startPrank(owner);
        vm.warp(block.timestamp + dps.soupCycleDuration());
        dps.vote(totalVotes, IDividendsPairStaking.Faction.DOG);
        dps.cycleSoup();
        vm.stopPrank();
    }
}

contract MucusFarmRescue is Initial {
    function setUp() public override {
        super.setUp();
        mintEthSale();
    }

    function test_revertsRescue() public {
        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i; i < 10; i++) {
            tokenIds[i] = i;
        }

        vm.prank(address(2));
        mucusFarm.addManyToMucusFarm(tokenIds);

        vm.prank(address(2));
        vm.expectRevert(bytes("Rescue mode not enabled"));
        mucusFarm.rescue(tokenIds);

        vm.prank(owner);
        mucusFarm.setRescueEnabled(true);
        vm.expectRevert(bytes("Cannot rescue frogs or dogs that you didn't stake"));
        mucusFarm.rescue(tokenIds);
    }

    function test_rescue() public {
        uint256[] memory tokenIds = new uint256[](10);
        for (uint256 i; i < 10; i++) {
            tokenIds[i] = i;
        }

        vm.prank(address(2));
        mucusFarm.addManyToMucusFarm(tokenIds);

        for (uint256 i; i < 10; i++) {
            assertEq(fnd.ownerOf(i), address(mucusFarm));
        }

        vm.prank(owner);
        mucusFarm.setRescueEnabled(true);
        vm.prank(address(2));
        mucusFarm.rescue(tokenIds);
        for (uint256 i; i < 10; i++) {
            assertEq(fnd.ownerOf(i), address(2));
        }
    }
}

contract MucusFarmOnlyOwner is Initial {
    event Paused(address account);
    event Unpaused(address account);

    function test_setResuceEnabled() public {
        vm.prank(owner);
        mucusFarm.setRescueEnabled(true);
        assertEq(mucusFarm.rescueEnabled(), true);
    }

    function test_setPausedTrue() public {
        vm.prank(owner);
        mucusFarm.setPaused(true);
        assertEq(mucusFarm.paused(), true);
    }
}
