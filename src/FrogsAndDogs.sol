// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.13;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/contracts/security/Pausable.sol";
import {VRFCoordinatorV2Interface} from "chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

contract FrogsAndDogs is ERC721, VRFConsumerBaseV2, Ownable, Pausable {
    uint256 public constant ETH_MINT_PRICE = 0.03131 ether;
    uint256 public constant MUCUS_MINT_PRICE = 6262 ether;
    uint256 public constant SUMMON_PRICE = 9393 ether;

    uint256 public constant FROGS_AND_DOGS_SUPPLY = 6000;
    uint256 public constant GIGAS_MAX_SUPPLY = 7001;
    uint256 public constant CHADS_MAX_SUPPLY = 7000;
    uint16 public constant STOLEN_MAGIC_NUMBER = 9393;

    uint256 public minted;
    uint256 public gigasMinted = 6001;
    uint256 public chadsMinted = 6000;

    uint256 public tokensPaidInEth = 2000; // 1/3 of the supply
    string public baseURI; // setup endpoint that grabs the images and denies access to images for tokenIds that aren't minted yet

    // see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
    bytes32 keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Storing each word costs about 20,000 gas,
    // so 100,000 is a safe default for this example contract. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 callbackGasLimit = 100000;

    // The default is 3, but you can set this higher.
    uint16 requestConfirmations = 3;

    enum Faction {
        FROG,
        DOG
    }

    struct Request {
        uint256 amount;
        bool fulfilled;
        bool stake;
        bool transform;
        Faction transformationType;
        Faction land;
        address parent;
    }

    mapping(uint256 => Request) public requests;

    VRFCoordinatorV2Interface public immutable vrfCoordinator;
    uint256 private subscriptionId;

    event RequestSent(uint256 indexed RequestId, uint256 amount);
    event RequestFulfilled(uint256 indexed RequestId, uint256 amount);

    constructor(uint256 _subscriptionId, string memory _baseURI) ERC721("Frogs and Dogs", "FND") {
        vrfCoordinator = VRFCoordinatorV2Interface(0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625);
        subscriptionId = _subscriptionId;
        baseURI = _baseURI;
    }

    function mint(uint256 amount, bool stake) external payable {
        require(minted + amount <= tokensPaidInEth, "All Dogs and Frogs for sale have been minted");
        require(amount > 0 && amount <= 10, "Invalid mint amount");
        require(amount * ETH_MINT_PRICE == msg.value, "Invalid payment amount");
        uint16[] memory tokenIds = stake ? new uint16[](amount) : new uint16[](0);

        for (uint256 i = 0; i < amount; i++) {
            _safeMint(_msgSender(), minted);
            if (stake) tokenIds[i] = minted;
            minted++;
        }

        if (stake) swampAndYard.addManyToNaturalHabitat(_msgSender(), tokenIds);
    }

    function breedAndAdpot(uint256 amount, bool stake) external payable {
        require(minted > tokensPaidInEth, "Breeding not available yet");
        require(minted + amount <= FROGS_AND_DOGS_SUPPLY, "All Dogs and Frogs have been minted");
        require(MUCUS_MINT_PRICE * amount <= mucus.balanceOf(msg.sender), "Insufficient $MUCUS balance");

        // Will revert if subscription is not set and funded.
        uint256 RequestId =
            vrfCoordinator.requestRandomWords(keyHash, subscriptionId, requestConfirmations, callbackGasLimit, 1);
        requests[RequestId] = Request({
            amount: amount,
            fulfilled: false,
            transform: false,
            transformationType: 0, // This doesn't matter here
            land: 0, // This doesn't matter here
            stake: stake,
            parent: msg.sender
        });

        mucus.burn(_msgSender(), amount * MUCUS_MINT_PRICE);

        emit RequestSent(RequestId, amount);
    }

    function transform(uint256[] tokenIds, Faction transformationType, Faction land, bool stake) external payable {
        require(tokenIds.length == 3 && isCorrectTypes(tokenIds, transformationType), "Must use 3 of the same types");
        require(transformationType != Faction.FROG || gigasMinted + 2 < GIGAS_MAX_SUPPLY, "All Gigas have been minted");
        require(transformationType != Faction.DOG || chadsMinted + 2 < CHADS_MAX_SUPPLY, "All Chads have been minted");

        // Will revert if subscription is not set and funded.
        uint256 RequestId =
            vrfCoordinator.requestRandomWords(keyHash, subscriptionId, requestConfirmations, callbackGasLimit, 1);
        requests[RequestId] = Request({
            amount: 1,
            fulfilled: false,
            transform: true,
            transformationType: transformationType,
            land: land,
            stake: stake,
            parent: msg.sender
        });

        for (uint256 i; i < tokenIds.length; i++) {
            FrogsAndDogs._burn(tokenIds[i]);
        }
        mucus.burn(_msgSender(), SUMMON_PRICE);

        emit RequestSent(RequestId, 1);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        require(!requests[_requestId].fulfilled, "request already fulfilled");

        uint256 rng = _randomWords[0];
        requests[_requestId].fulfilled = true;

        if (!requests[_requestId].transform) {
            mintOrStealFrogOrDog(
                requests[_requestId].stake, requests[_requestId].amount, requests[_requestId].parent, rng
            );
        } else {
            mintOrBustGigaOrChad(
                requests[_requestId].transformationType,
                requests[_requestId].land,
                requests[_requestId].parent,
                requests[_requestId].stake,
                rng
            );
        }

        emit RequestFulfilled(_requestId, requests[_requestId].amount);
    }

    function mintOrStealFrogOrDog(bool stake, uint256 amount, address parent, uint256 rng) internal {
        uint16[] memory tokenIds = stake ? new uint16[](amount) : new uint16[](0);
        address recipient = selectRecipient(rng, parent);

        for (uint256 i = 0; i < amount; i++) {
            if (!stake || recipient != parent) {
                _safeMint(recipient, minted);
                tokenIds[i] = STOLEN_MAGIC_NUMBER;
            } else {
                _safeMint(address(swampAndYard), minted);
                tokenIds[i] = minted;
            }
            minted++;
        }

        if (stake) swampAndYard.addManyToNaturalHabitat(parent, tokenIds);
    }

    function mintOrBustGigaOrChad(Faction transformationType, Faction land, address parent, bool stake, uint256 rng)
        internal
    {
        require(rng % 5 != 0, "Bust, summoning failed");

        uint256 tokenId = transformationType == Faction.FROG ? gigasMinted : chadsMinted;
        if (transformationType == Faction.FROG) {
            _safeMint(stake ? address(swampAndYard) : parent, gigasMinted);
            gigasMinted += 2;
        } else {
            _safeMint(stake ? address(swampAndYard) : parent, chadsMinted);
            chadsMinted += 2;
        }
        minted++;

        if (stake) swampAndYard.stakeGigaOrChad(tokenId, land);
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        // Hardcode the swampAndYard's approval so that users don't have to waste gas approving
        if (_msgSender() != address(swampAndYard)) {
            require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        }
        _transfer(from, to, tokenId);
    }

    /**
     * the first 20% (ETH purchases) go to the minter
     * the remaining 80% have a 10% chance to be given to a random staked wolf
     * @param rng a random value to select a recipient from
     * @param parent the address of the user that initiated the breeding request
     * @return recipient address of the recipient (either the minter or the Wolf thief's owner)
     */
    function selectRecipient(uint256 rng, address parent) internal view returns (address) {
        uint256 seed = uint256(keccak256(abi.encodePacked(rng, minted)));
        if (seed % 10 != 0) return parent; // 10% chance to steal
        // If it's minting a dog, chance for giga frog to steal. vice versa
        address thief;
        if (minted % 2 == 0) {
            thief = swampAndYards.randomGigaFrogOwner(seed);
        } else {
            thief = swampAndYards.randomChadDogOwner(seed);
        }

        if (thief == address(0x0)) return parent;
        return thief;
    }

    function isCorrectTypes(uint256[] tokenIds, Faction transformationType)
        internal
        view
        returns (uint256 cumulative)
    {
        for (uint256 i; i < tokenIds.length; i++) {
            if (tokenIds[i] % 2 != transformationType) return false;
        }

        return true;
    }

    function setSwampAndYard(address _swampAndYard) external onlyOwner {
        swampAndYard = ISwampAndYard(_swampAndYard);
    }

    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function setPaidTokens(uint256 _paidTokens) external onlyOwner {
        tokensPaidInEth = _paidTokens;
    }

    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    function setBaseURI(string memory uri) public onlyOwner {
        baseURI = uri;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
