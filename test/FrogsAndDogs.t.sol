pragma solidity ^0.8.13;

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
    uint256 public constant MUCUS_MINT_PRICE = 6262 ether;
    uint256 public constant FROGS_AND_DOGS_SUPPLY = 6000;

    uint256 public gigasMinted = 6001;
    uint256 public chadsMinted = 6000;
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

    function setUp() public {
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
        mucus.setDividendsPairStaking(address(dps));

        fnd = new FrogsAndDogs(_subscriptionId, "", "", address(vrfCoordinator), address(mucus), address(dps));
        mucusFarm = new MucusFarm(address(fnd), address(mucus), address(dps));
        fnd.setMucusFarm(address(mucusFarm));

        mucus.setMucusFarm(address(mucusFarm));
        mucus.setFrogsAndDogs(address(fnd));

        vrfCoordinator.addConsumer(_subscriptionId, address(fnd));

        vm.stopPrank();
    }

    function mintEthSale() public {
        for (uint256 i; i < tokensPaidInEth / 10; i++) {
            fnd.mint{value: ETH_MINT_PRICE * 10}(10, false);
        }
    }
}

contract FndMint is Initial {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event TokenStaked(address indexed parent, uint256 tokenId);

    function testRevertsMint() public {
        vm.startPrank(address(2));
        vm.deal(address(2), 10000 ether);

        // error cases
        vm.expectRevert(bytes("Invalid mint amount"));
        fnd.mint{value: 0}(0, false);

        vm.expectRevert(bytes("Invalid mint amount"));
        fnd.mint{value: ETH_MINT_PRICE * 11}(11, false);

        vm.expectRevert(bytes("Invalid payment amount"));
        fnd.mint{value: ETH_MINT_PRICE * 9}(10, false);

        for (uint256 i; i < tokensPaidInEth / 10; i++) {
            fnd.mint{value: ETH_MINT_PRICE * 10}(10, false);
        }
        vm.expectRevert(bytes("All Dogs and Frogs for sale have been minted"));
        fnd.mint{value: ETH_MINT_PRICE}(1, false);
    }

    function testMintWithoutStaking() public {
        vm.startPrank(address(2));
        vm.expectEmit(true, true, true, true);
        for (uint256 i; i < 10; i++) {
            emit Transfer(address(0), address(2), i);
        }
        fnd.mint{value: ETH_MINT_PRICE * 10}(10, false);

        for (uint256 i; i < 10; i++) {
            assertEq(fnd.ownerOf(i), address(2));
        }
        assertEq(fnd.balanceOf(address(2)), 10);
    }

    function testMintWithStaking() public {
        vm.startPrank(address(2));
        vm.expectEmit(true, true, true, true);
        for (uint256 i; i < 10; i++) {
            emit Transfer(address(0), address(mucusFarm), i);
        }
        for (uint256 i; i < 10; i++) {
            emit TokenStaked(address(2), i);
        }
        fnd.mint{value: ETH_MINT_PRICE * 10}(10, true);

        for (uint256 i; i < 10; i++) {
            assertEq(fnd.ownerOf(i), address(mucusFarm), "ownerOf");
        }
        assertEq(fnd.balanceOf(address(mucusFarm)), 10, "balanceOf");

        for (uint256 i; i < 1; i++) {
            (
                address stakingOwner,
                uint256 lockingEndTime,
                uint256 previousClaimTimestamp,
                uint256 previousTaxPer,
                uint256 previousSoupIndex,
                uint256 gigaOrChadIndex
            ) = mucusFarm.farm(i);

            assertEq(stakingOwner, address(2), "owner");
            assertEq(lockingEndTime, block.timestamp + 3 days);
            assertEq(previousClaimTimestamp, block.timestamp, "previousClaimTimestamp");
            assertEq(previousTaxPer, 0, "previousTaxPer");
            assertEq(previousSoupIndex, 0, "previousSoupIndex");
            assertEq(gigaOrChadIndex, 0, "gigaOrChadIndex");
        }

        vm.stopPrank();
    }
}

contract FndBreedAndAdopt is Initial {
    function test_revertsBreedAndAdopt() public {
        vm.startPrank(address(2));
        vm.deal(address(2), 10000 ether);

        vm.expectRevert(bytes("Breeding not available yet"));
        fnd.breedAndAdopt(10, false);

        mintEthSale();

        vm.expectRevert(bytes("Invalid mint amount"));
        fnd.breedAndAdopt(0, false);

        vm.expectRevert(bytes("Invalid mint amount"));
        fnd.breedAndAdopt(11, false);

        vm.expectRevert(bytes("Insufficient $MUCUS balance"));
        fnd.breedAndAdopt(10, false);

        vm.stopPrank();

        vm.prank(owner);
        mucus.transfer(address(2), 3000 * 1e8 ether);
        vm.startPrank(address(2));

        for (uint256 i; i < (FROGS_AND_DOGS_SUPPLY - tokensPaidInEth) / 10; i++) {
            fnd.breedAndAdopt(10, true);
            vrfCoordinator.fulfillRandomWords(i + 1, address(fnd));
        }

        vm.expectRevert(bytes("All Dogs and Frogs have been minted"));
        fnd.breedAndAdopt(1, false);

        vm.stopPrank();
    }

    function test_breedAndNotStake() public {
        vm.deal(owner, 10000 ether);
        vm.startPrank(owner);
        mintEthSale();
        vm.stopPrank();

        vm.prank(owner);
        mucus.transfer(address(2), 3000 * 1e8 ether);
        uint256 mucusBalanceBefore = mucus.balanceOf(address(2));

        vm.prank(address(2));
        fnd.breedAndAdopt(1, false);
        vrfCoordinator.fulfillRandomWords(1, address(fnd));

        assertEq(mucus.balanceOf(address(2)), mucusBalanceBefore - MUCUS_MINT_PRICE, "mucus balanceOf");
        assertEq(fnd.balanceOf(address(2)), 1, "fnd balanceOf");
    }

    function test_breedAndStake() public {
        vm.deal(owner, 10000 ether);
        vm.startPrank(owner);
        mintEthSale();
        vm.stopPrank();

        vm.prank(owner);
        mucus.transfer(address(2), 3000 * 1e8 ether);
        uint256 mucusBalanceBefore = mucus.balanceOf(address(2));

        vm.prank(address(2));
        fnd.breedAndAdopt(1, true);
        vrfCoordinator.fulfillRandomWords(1, address(fnd));

        assertEq(mucus.balanceOf(address(2)), mucusBalanceBefore - MUCUS_MINT_PRICE, "mucus balanceOf");
        assertEq(fnd.balanceOf(address(2)), 0, "fnd balanceOf user");
        assertEq(fnd.balanceOf(address(mucusFarm)), 1, "fnd balanceOf mucusFarm");
    }
}

contract FndTransform is Initial {
    function test_revertsTransform() public {
        vm.startPrank(address(2));
        deal(address(2), 10000 ether);
        mintEthSale();
        vm.stopPrank();

        vm.prank(owner);
        mucus.transfer(address(2), 3000 * 1e8 ether);
        vm.prank(address(2));

        vm.expectRevert(bytes("Must use 3 of the same types"));
        uint256[] memory tokenIds = new uint256[](3);
        for (uint256 i; i < tokenIds.length; i++) {
            tokenIds[i] = i;
        }
        fnd.transform(tokenIds, dog, false);

        breedMultiple();

        transformMultipleDogs(3732);
        transformMultipleFrogs(3805);

        vm.startPrank(address(2));
        vm.expectRevert(bytes("All Chads have been minted"));
        tokenIds[0] = 3732;
        tokenIds[1] = 3734;
        tokenIds[2] = 3736;
        fnd.transform(tokenIds, dog, false);

        vm.expectRevert(bytes("All Gigas have been minted"));
        tokenIds[0] = 3733;
        tokenIds[1] = 3735;
        tokenIds[2] = 3737;
        fnd.transform(tokenIds, frog, false);
        vm.stopPrank();
    }

    function test_transformSuccessfulAndNotStake() public {
        vm.startPrank(address(2));
        deal(address(2), 10000 ether);
        mintEthSale();
        vm.stopPrank();

        vm.prank(owner);
        mucus.transfer(address(2), 3000 * 1e8 ether);

        uint256 balanceBefore = fnd.balanceOf(address(2));
        uint256 requestId = vrfCoordinator.s_nextRequestId();

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 0;
        tokenIds[1] = 2;
        tokenIds[2] = 4;
        vm.prank(address(2));
        fnd.transform(tokenIds, dog, false);
        vrfCoordinator.fulfillRandomWords(requestId, address(fnd));

        assertEq(fnd.balanceOf(address(2)), balanceBefore - 3 + 1, "balance of user");
        assertEq(fnd.ownerOf(6000), address(2), "owner of new token");
    }

    function test_transformSuccessfulAndStake() public {
        vm.startPrank(address(2));
        deal(address(2), 10000 ether);
        mintEthSale();
        vm.stopPrank();

        vm.prank(owner);
        mucus.transfer(address(2), 3000 * 1e8 ether);

        uint256 balanceBefore = fnd.balanceOf(address(2));
        uint256 requestId = vrfCoordinator.s_nextRequestId();

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 0;
        tokenIds[1] = 2;
        tokenIds[2] = 4;
        vm.prank(address(2));
        fnd.transform(tokenIds, dog, true);
        vrfCoordinator.fulfillRandomWords(requestId, address(fnd));

        assertEq(fnd.balanceOf(address(2)), balanceBefore - 3, "balance of user");
        assertEq(fnd.ownerOf(6000), address(mucusFarm), "owner of new token");
    }

    function test_transformFail() public {
        vm.startPrank(address(2));
        deal(address(2), 10000 ether);
        mintEthSale();
        vm.stopPrank();

        vm.prank(owner);
        mucus.transfer(address(2), 3000 * 1e8 ether);

        transformMultipleDogs(19);

        uint256 balanceBefore = fnd.balanceOf(address(2));

        uint256 requestId = vrfCoordinator.s_nextRequestId();
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 30;
        tokenIds[1] = 32;
        tokenIds[2] = 34;
        vm.prank(address(2));
        fnd.transform(tokenIds, dog, false);
        vrfCoordinator.fulfillRandomWords(requestId, address(fnd));

        assertEq(fnd.balanceOf(address(2)), balanceBefore - 3, "balance of user");
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

    function breedMultiple() public {
        vm.startPrank(address(2));
        for (uint256 i; i < (2000) / 10; i++) {
            fnd.breedAndAdopt(10, false);
            vrfCoordinator.fulfillRandomWords(i + 1, address(fnd));
        }
        vm.stopPrank();
    }
}

contract FndBreedAndStolen is Initial {
    address public stealer = address(3);

    function test_breedStakeAndNotStolenSinceNoSouped() public {
        vm.startPrank(stealer);
        deal(stealer, 10000 ether);
        mintEthSale();
        vm.stopPrank();

        vm.startPrank(owner);
        mucus.transfer(stealer, 1500 * 1e8 ether);
        mucus.transfer(address(2), 1500 * 1e8 ether);
        vm.stopPrank();

        // mint and stake chad dog
        uint256 requestId = vrfCoordinator.s_nextRequestId();
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 0;
        tokenIds[1] = 2;
        tokenIds[2] = 4;

        vm.startPrank(stealer);
        fnd.transform(tokenIds, dog, true);
        vrfCoordinator.fulfillRandomWords(requestId, address(fnd));

        // breed and get stolen
        vm.prank(address(2));
        fnd.breedAndAdopt(3, false);
        vrfCoordinator.fulfillRandomWords(requestId + 1, address(fnd));

        assertEq(fnd.balanceOf(address(2)), 3, "balance of user");
        assertEq(fnd.ownerOf(2002), address(2), "owner of");
    }

    function test_breedStakeAndNotStolenSinceSoupedUp() public {
        vm.startPrank(stealer);
        deal(stealer, 10000 ether);
        mintEthSale();
        vm.stopPrank();

        vm.startPrank(owner);
        mucus.transfer(stealer, 1500 * 1e8 ether);
        mucus.transfer(address(2), 1500 * 1e8 ether);
        vm.stopPrank();

        // mint and stake chad dog
        uint256 requestId = vrfCoordinator.s_nextRequestId();
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 0;
        tokenIds[1] = 2;
        tokenIds[2] = 4;

        vm.startPrank(stealer);
        fnd.transform(tokenIds, dog, true);
        vrfCoordinator.fulfillRandomWords(requestId, address(fnd));

        // breed and get stolen
        vm.prank(address(2));
        fnd.breedAndAdopt(10, false);
        vrfCoordinator.fulfillRandomWords(requestId + 1, address(fnd));

        assertEq(fnd.balanceOf(address(2)), 10, "balance of user");
        assertEq(fnd.ownerOf(2009), address(2), "owner of");
    }

    function test_breedStakeAndStolen() public {
        vm.startPrank(stealer);
        deal(stealer, 10000 ether);
        mintEthSale();
        vm.stopPrank();

        vm.startPrank(owner);
        mucus.transfer(stealer, 1500 * 1e8 ether);
        mucus.transfer(address(2), 1500 * 1e8 ether);
        vm.stopPrank();

        // mint and stake chad dog
        uint256 requestId = vrfCoordinator.s_nextRequestId();
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 3;
        tokenIds[2] = 5;

        vm.startPrank(stealer);
        fnd.transform(tokenIds, frog, true);
        vrfCoordinator.fulfillRandomWords(requestId, address(fnd));

        // breed and get stolen
        vm.prank(address(2));
        fnd.breedAndAdopt(3, false);
        vrfCoordinator.fulfillRandomWords(requestId + 1, address(fnd));

        assertEq(fnd.balanceOf(address(2)), 2, "balance of user");
        assertEq(fnd.ownerOf(2002), stealer, "owner of");
    }
}

contract FndOnlyOwner is Initial {
    function test_withdrawEth() public {
        deal(address(fnd), 1000 ether);

        uint256 balanceBefore = owner.balance;
        vm.prank(owner);
        fnd.withdraw();

        assertEq(owner.balance, balanceBefore + 1000 ether, "balance");
    }

    function test_setPaidTokens() public {
        vm.prank(owner);
        fnd.setPaidTokens(3000);

        assertEq(fnd.tokensPaidInEth(), 3000, "tokensPaidInEth");
    }

    function test_setPaused() public {
        vm.prank(owner);
        fnd.setPaused(true);

        assertEq(fnd.paused(), true, "paused");
    }

    function test_setBaseUri() public {
        vm.prank(owner);
        fnd.setBaseURI("asd");

        assertEq(fnd.baseURI(), "asd", "baseURI");
    }
}
