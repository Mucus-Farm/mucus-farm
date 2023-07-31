pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Mucus} from "../src/Mucus.sol";
import {DividendsPairStaking} from "../src/DividendsPairStaking.sol";
import {FrogsAndDogs} from "../src/FrogsAndDogs.sol";
import {IFrogsAndDogs} from "../src/interfaces/IFrogsAndDogs.sol";
import {MucusFarm} from "../src/MucusFarm.sol";
import {VRFCoordinatorV2Mock} from "./mocks/VRFCoordinatorV2Mock.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Merkle} from "murky/Merkle.sol";

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
    uint256 teamAmount = 20;

    Mucus public mucus;
    DividendsPairStaking public dps;
    FrogsAndDogs public fnd;
    MucusFarm public mucusFarm;
    Merkle public m;

    IUniswapV2Router02 public router;
    IUniswapV2Pair public pair;
    IERC20 public weth;
    VRFCoordinatorV2Mock public vrfCoordinator;

    IFrogsAndDogs.Faction frog = IFrogsAndDogs.Faction.FROG;
    IFrogsAndDogs.Faction dog = IFrogsAndDogs.Faction.DOG;

    address public teamWallet = address(123);
    address public owner = address(1);
    bytes32[] public data;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 16183456);
        vm.startPrank(owner);

        uint96 _baseFee = 100000000000000000;
        uint96 _gasPriceLink = 1000000000;
        bytes32 _keyHash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;
        vrfCoordinator = new VRFCoordinatorV2Mock(_baseFee, _gasPriceLink);

        uint64 _subscriptionId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(_subscriptionId, 1000 ether);

        address _uniswapRouter02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        mucus = new Mucus(teamWallet);
        dps = new DividendsPairStaking(address(mucus));
        mucus.setDividendsPairStaking(address(dps));

        m = new Merkle();
        data = new bytes32[](4);
        data[0] = keccak256(abi.encodePacked(address(0)));
        data[1] = keccak256(abi.encodePacked(address(1)));
        data[2] = keccak256(abi.encodePacked(address(2)));
        data[3] = keccak256(abi.encodePacked(address(3)));
        bytes32 root = m.getRoot(data);

        fnd =
        new FrogsAndDogs(ETH_MINT_PRICE, root, _subscriptionId, "", "", address(vrfCoordinator), _keyHash, address(mucus), address(dps));
        mucusFarm = new MucusFarm(address(fnd), address(mucus), address(dps));
        fnd.setMucusFarm(address(mucusFarm));

        mucus.setMucusFarm(address(mucusFarm));
        mucus.setFrogsAndDogs(address(fnd));

        vrfCoordinator.addConsumer(_subscriptionId, address(fnd));

        vm.stopPrank();
    }

    function mintEthSale() public {
        for (uint256 i; i < (tokensPaidInEth - teamAmount) / 10; i++) {
            fnd.mint{value: ETH_MINT_PRICE * 10}(10);
        }
    }
}

contract FndWhitelistMint is Initial {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event TokenStaked(address indexed parent, uint256 tokenId);

    function testRevertsWhitelistMint() public {
        vm.startPrank(address(2));

        bytes32[] memory proof = m.getProof(data, 2);
        bytes32[] memory invalidProof = m.getProof(data, 0);

        // error cases
        vm.expectRevert(bytes("Invalid proof"));
        fnd.whitelistMint(0, invalidProof);

        vm.expectRevert(bytes("Invalid mint amount"));
        fnd.whitelistMint(0, proof);

        vm.expectRevert(bytes("Invalid mint amount"));
        fnd.whitelistMint(11, proof);

        fnd.whitelistMint(10, proof);
        vm.expectRevert(bytes("Cannot mint more than 10 whitelist tokens"));
        fnd.whitelistMint(1, proof);

        vm.stopPrank();
    }

    function testWhitelistMint() public {
        vm.startPrank(address(2));

        bytes32[] memory proof = m.getProof(data, 2);

        vm.expectEmit(true, true, true, true);
        for (uint256 i; i < 10; i++) {
            emit Transfer(address(0), address(2), teamAmount + i);
        }
        fnd.whitelistMint(10, proof);

        for (uint256 i; i < 10; i++) {
            assertEq(fnd.ownerOf(teamAmount + i), address(2));
        }
        assertEq(fnd.balanceOf(address(2)), 10);
    }
}

contract FndMint is Initial {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event TokenStaked(address indexed parent, uint256 tokenId);

    function setUp() public override {
        super.setUp();
        vm.startPrank(address(owner));
        fnd.setPublicMintStarted();
    }

    function testRevertsMint() public {
        vm.startPrank(address(2));
        vm.deal(address(2), 10000 ether);

        // error cases
        vm.expectRevert(bytes("Invalid mint amount"));
        fnd.mint{value: 0}(0);

        vm.expectRevert(bytes("Invalid mint amount"));
        fnd.mint{value: ETH_MINT_PRICE * 11}(11);

        vm.expectRevert(bytes("Invalid payment amount"));
        fnd.mint{value: ETH_MINT_PRICE * 9}(10);

        for (uint256 i; i < (tokensPaidInEth - teamAmount) / 10; i++) {
            fnd.mint{value: ETH_MINT_PRICE * 10}(10);
        }
        vm.expectRevert(bytes("All Dogs and Frogs for sale have been minted"));
        fnd.mint{value: ETH_MINT_PRICE}(1);
    }

    function testMint() public {
        vm.startPrank(address(2));
        vm.expectEmit(true, true, true, true);
        for (uint256 i; i < 10; i++) {
            emit Transfer(address(0), address(2), teamAmount + i);
        }
        fnd.mint{value: ETH_MINT_PRICE * 10}(10);

        for (uint256 i; i < 10; i++) {
            assertEq(fnd.ownerOf(teamAmount + i), address(2));
        }
        assertEq(fnd.balanceOf(address(2)), 10);
    }
}

contract FndBreedAndAdopt is Initial {
    function setUp() public override {
        super.setUp();
        vm.startPrank(address(owner));
        fnd.setPublicMintStarted();
    }

    function test_revertsBreedAndAdopt() public {
        vm.startPrank(address(2));
        vm.deal(address(2), 10000 ether);

        vm.expectRevert(bytes("Breeding not available yet"));
        fnd.breedAndAdopt(10);

        mintEthSale();

        vm.expectRevert(bytes("Invalid mint amount"));
        fnd.breedAndAdopt(0);

        vm.expectRevert(bytes("Invalid mint amount"));
        fnd.breedAndAdopt(11);

        vm.expectRevert(bytes("Insufficient $MUCUS balance"));
        fnd.breedAndAdopt(10);

        vm.stopPrank();

        vm.prank(owner);
        mucus.transfer(address(2), 3000 * 1e8 ether);
        vm.startPrank(address(2));

        for (uint256 i; i < (FROGS_AND_DOGS_SUPPLY - tokensPaidInEth) / 10; i++) {
            fnd.breedAndAdopt(10);
            vrfCoordinator.fulfillRandomWords(i + 1, address(fnd));
        }

        vm.expectRevert(bytes("All Dogs and Frogs have been minted"));
        fnd.breedAndAdopt(1);

        vm.stopPrank();
    }

    function test_breedAndAdopt() public {
        vm.deal(owner, 10000 ether);
        vm.startPrank(owner);
        mintEthSale();
        vm.stopPrank();

        vm.prank(owner);
        mucus.transfer(address(2), 3000 * 1e8 ether);
        uint256 mucusBalanceBefore = mucus.balanceOf(address(2));

        vm.prank(address(2));
        fnd.breedAndAdopt(1);
        vrfCoordinator.fulfillRandomWords(1, address(fnd));

        assertEq(mucus.balanceOf(address(2)), mucusBalanceBefore - MUCUS_MINT_PRICE, "mucus balanceOf");
        assertEq(fnd.balanceOf(address(2)), 1, "fnd balanceOf");
    }
}

contract FndTransform is Initial {
    function setUp() public override {
        super.setUp();
        vm.startPrank(address(owner));
        fnd.setPublicMintStarted();
    }

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
            tokenIds[i] = teamAmount + i;
        }
        fnd.transform(tokenIds, dog);

        breedMultiple();

        transformMultipleDogs(3732);
        transformMultipleFrogs(3805);

        vm.startPrank(address(2));
        vm.expectRevert(bytes("All Chads have been minted"));
        tokenIds[0] = 3732;
        tokenIds[1] = 3734;
        tokenIds[2] = 3736;
        fnd.transform(tokenIds, dog);

        vm.expectRevert(bytes("All Gigas have been minted"));
        tokenIds[0] = 3733;
        tokenIds[1] = 3735;
        tokenIds[2] = 3737;
        fnd.transform(tokenIds, frog);
        vm.stopPrank();
    }

    function test_transformSuccessful() public {
        vm.startPrank(address(2));
        deal(address(2), 10000 ether);
        mintEthSale();
        vm.stopPrank();

        vm.prank(owner);
        mucus.transfer(address(2), 3000 * 1e8 ether);

        uint256 balanceBefore = fnd.balanceOf(address(2));
        uint256 requestId = vrfCoordinator.s_nextRequestId();

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 20;
        tokenIds[1] = 22;
        tokenIds[2] = 24;
        vm.prank(address(2));
        fnd.transform(tokenIds, dog);
        vrfCoordinator.fulfillRandomWords(requestId, address(fnd));

        assertEq(fnd.balanceOf(address(2)), balanceBefore - 3 + 1, "balance of user");
        assertEq(fnd.ownerOf(6000), address(2), "owner of new token");
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
        tokenIds[0] = 40;
        tokenIds[1] = 42;
        tokenIds[2] = 44;
        vm.prank(address(2));
        fnd.transform(tokenIds, dog);
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
            tokenIds[0] = teamAmount + i;
            tokenIds[1] = teamAmount + i + 2;
            tokenIds[2] = teamAmount + i + 4;
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
            tokenIds[0] = teamAmount + i;
            tokenIds[1] = teamAmount + i + 2;
            tokenIds[2] = teamAmount + i + 4;
            fnd.transform(tokenIds, frog);

            vrfCoordinator.fulfillRandomWords(requestId + j, address(fnd));
            j++;
        }

        vm.stopPrank();
    }

    function breedMultiple() public {
        vm.startPrank(address(2));
        for (uint256 i; i < (2000) / 10; i++) {
            fnd.breedAndAdopt(10);
            vrfCoordinator.fulfillRandomWords(i + 1, address(fnd));
        }
        vm.stopPrank();
    }
}

contract FndBreedAndStolen is Initial {
    address public stealer = address(3);

    function setUp() public override {
        super.setUp();
        vm.startPrank(address(owner));
        fnd.setPublicMintStarted();
    }

    function test_breedAndNotStolenSinceNoSouped() public {
        vm.startPrank(stealer);
        deal(stealer, 10000 ether);
        mintEthSale();
        vm.stopPrank();

        vm.startPrank(owner);
        mucus.transfer(stealer, 1500 * 1e8 ether);
        mucus.transfer(address(2), 1500 * 1e8 ether);
        vm.stopPrank();

        // breed and get stolen
        uint256 requestId = vrfCoordinator.s_nextRequestId();
        vm.prank(address(2));
        fnd.breedAndAdopt(3);
        vrfCoordinator.fulfillRandomWords(requestId, address(fnd));

        assertEq(fnd.balanceOf(address(2)), 3, "balance of user");
        assertEq(fnd.ownerOf(2002), address(2), "owner of");
    }

    function test_breedAndNotStolenSinceSoupedUp() public {
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
        tokenIds[0] = teamAmount + 0;
        tokenIds[1] = teamAmount + 2;
        tokenIds[2] = teamAmount + 4;

        vm.startPrank(stealer);
        fnd.transform(tokenIds, dog);
        vrfCoordinator.fulfillRandomWords(requestId, address(fnd));
        uint256[] memory chadId = new uint256[](1);
        chadId[0] = 6000;
        mucusFarm.addManyToMucusFarm(chadId);
        vm.stopPrank();

        // breed and get stolen
        vm.prank(address(2));
        fnd.breedAndAdopt(10);
        vrfCoordinator.fulfillRandomWords(requestId + 1, address(fnd));

        assertEq(fnd.balanceOf(address(2)), 10, "balance of user");
        assertEq(fnd.ownerOf(2009), address(2), "owner of");
    }

    function test_breedAndStolen() public {
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
        tokenIds[0] = teamAmount + 1;
        tokenIds[1] = teamAmount + 3;
        tokenIds[2] = teamAmount + 5;

        vm.startPrank(stealer);
        fnd.transform(tokenIds, frog);
        vrfCoordinator.fulfillRandomWords(requestId, address(fnd));
        uint256[] memory frogId = new uint256[](1);
        frogId[0] = 6001;
        mucusFarm.addManyToMucusFarm(frogId);
        vm.stopPrank();

        // breed and get stolen
        vm.prank(address(2));
        fnd.breedAndAdopt(3);
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
