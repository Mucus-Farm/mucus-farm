// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.13;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/contracts/security/Pausable.sol";
import {MerkleProof} from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {VRFCoordinatorV2Interface} from "chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {IFrogsAndDogs} from "./interfaces/IFrogsAndDogs.sol";
import {IMucusFarm} from "./interfaces/IMucusFarm.sol";
import {IMucus} from "./interfaces/IMucus.sol";
import {IDividendsPairStaking} from "./interfaces/IDividendsPairStaking.sol";

contract FrogsAndDogs is IFrogsAndDogs, ERC721, VRFConsumerBaseV2, Ownable, Pausable {
    uint256 public constant MUCUS_MINT_PRICE = 6262 ether;
    uint256 public constant SUMMON_PRICE = 9393 ether;
    uint256 public immutable ETH_MINT_PRICE;
    bytes32 public immutable WHITELIST_MERKLE_ROOT;

    uint256 public constant FROGS_AND_DOGS_SUPPLY = 6000;
    uint256 public constant GIGAS_MAX_SUPPLY = 7001;
    uint256 public constant CHADS_MAX_SUPPLY = 7000;

    uint256 public minted;
    uint256 public gigasMinted = 6001;
    uint256 public chadsMinted = 6000;

    uint256 public whitelistMintSupply = 1000;
    uint256 public tokensPaidInEth = 2000;
    string public baseURI;
    string public contractURI;

    bool public publicMintStarted;
    mapping(address => uint256) private whitelistMinted;

    // see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
    bytes32 public immutable keyHash;

    uint32 public constant callbackGasLimit = 500000;

    // The default is 3, but you can set this higher.
    uint16 public constant requestConfirmations = 3;

    mapping(uint256 => Request) public requests;
    uint64 private immutable subscriptionId;

    VRFCoordinatorV2Interface public immutable vrfCoordinator;
    IDividendsPairStaking dividendsPairStaking;
    IMucusFarm public mucusFarm;
    IMucus public mucus;

    constructor(
        uint256 _ETH_MINT_PRICE,
        bytes32 _WHITELIST_MERKLE_ROOT,
        uint64 _subscriptionId,
        string memory _initialBaseURI,
        string memory _initialContractURI,
        address _vrfCoordinator,
        bytes32 _keyHash,
        address _mucus,
        address _dividendsPerStaking
    ) ERC721("Frogs and Dogs", "FND") VRFConsumerBaseV2(_vrfCoordinator) {
        ETH_MINT_PRICE = _ETH_MINT_PRICE;
        WHITELIST_MERKLE_ROOT = _WHITELIST_MERKLE_ROOT;
        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        mucus = IMucus(_mucus);
        dividendsPairStaking = IDividendsPairStaking(_dividendsPerStaking);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        baseURI = _initialBaseURI;
        contractURI = _initialContractURI;
        _mint(20);
    }

    function whitelistMint(uint256 amount, bytes32[] calldata proof) external whenNotPaused {
        require(!publicMintStarted, "Public minting has already started");
        require(
            MerkleProof.verifyCalldata(proof, WHITELIST_MERKLE_ROOT, keccak256(abi.encodePacked(_msgSender()))),
            "Invalid proof"
        );
        require(amount > 0 && amount <= 10, "Invalid mint amount");
        require(minted + amount < whitelistMintSupply, "All whitelist tokens have been minted");
        require(whitelistMinted[_msgSender()] + amount <= 10, "Cannot mint more than 10 whitelist tokens");

        _mint(amount);
        whitelistMinted[_msgSender()] += amount;
    }

    function mint(uint256 amount) external payable whenNotPaused {
        require(publicMintStarted, "Public minting has not started yet");
        require(amount > 0 && amount <= 10, "Invalid mint amount");
        require(minted + amount <= tokensPaidInEth, "All Dogs and Frogs for sale have been minted");
        require(amount * ETH_MINT_PRICE == msg.value, "Invalid payment amount");

        _mint(amount);
    }

    function _mint(uint256 amount) internal {
        for (uint256 i = 0; i < amount;) {
            _mint(_msgSender(), minted);
            minted++;
            unchecked {
                i++;
            }
        }
    }

    function breedAndAdopt(uint256 amount) external payable whenNotPaused {
        require(minted >= tokensPaidInEth, "Breeding not available yet");
        require(amount > 0 && amount <= 10, "Invalid mint amount");
        require(minted + amount <= FROGS_AND_DOGS_SUPPLY, "All Dogs and Frogs have been minted");
        require(MUCUS_MINT_PRICE * amount <= mucus.balanceOf(_msgSender()), "Insufficient $MUCUS balance");

        // Will revert if subscription is not set and funded.
        uint256 RequestId =
            vrfCoordinator.requestRandomWords(keyHash, subscriptionId, requestConfirmations, callbackGasLimit, 1);
        requests[RequestId] = Request({
            amount: amount,
            transform: false,
            transformationType: Faction.FROG, // This doesn't matter here
            parent: msg.sender
        });

        mucus.burn(_msgSender(), amount * MUCUS_MINT_PRICE);
    }

    function transform(uint256[] calldata tokenIds, Faction transformationType) external payable whenNotPaused {
        require(tokenIds.length == 3 && _isCorrectTypes(tokenIds, transformationType), "Must use 3 of the same types");
        require(transformationType != Faction.FROG || gigasMinted + 2 <= GIGAS_MAX_SUPPLY, "All Gigas have been minted");
        require(transformationType != Faction.DOG || chadsMinted + 2 <= CHADS_MAX_SUPPLY, "All Chads have been minted");

        // Will revert if subscription is not set and funded.
        uint256 RequestId =
            vrfCoordinator.requestRandomWords(keyHash, subscriptionId, requestConfirmations, callbackGasLimit, 1);
        requests[RequestId] =
            Request({amount: 1, transform: true, transformationType: transformationType, parent: _msgSender()});

        for (uint256 i; i < tokenIds.length;) {
            require(ownerOf(tokenIds[i]) == _msgSender(), "Must own all tokens");
            _burn(tokenIds[i]);
            unchecked {
                i++;
            }
        }
        mucus.burn(_msgSender(), SUMMON_PRICE);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        uint256 rng = _randomWords[0];

        if (!requests[_requestId].transform) {
            _mintOrStealFrogOrDog(requests[_requestId].amount, requests[_requestId].parent, rng);
        } else {
            _mintOrBustGigaOrChad(requests[_requestId].transformationType, requests[_requestId].parent, rng);
        }
    }

    function _mintOrStealFrogOrDog(uint256 amount, address parent, uint256 rng) internal {
        for (uint256 i = 0; i < amount;) {
            address recipient = selectRecipient(rng, parent);
            _mint(recipient, minted);
            minted++;
            unchecked {
                i++;
            }
        }
    }

    function _mintOrBustGigaOrChad(Faction transformationType, address parent, uint256 rng) internal {
        uint256 tokenId = transformationType == Faction.FROG ? gigasMinted : chadsMinted;
        if (rng % 5 != 0) {
            if (transformationType == Faction.FROG) {
                _mint(parent, tokenId);
                gigasMinted += 2;
            } else {
                _mint(parent, tokenId);
                chadsMinted += 2;
            }
        }

        emit Transformation(parent, tokenId, rng % 5 != 0);
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        // Hardcode the mucusFarm's approval so that users don't have to waste gas approving
        if (_msgSender() != address(mucusFarm)) {
            require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        }
        _transfer(from, to, tokenId);
    }

    function selectRecipient(uint256 rng, address parent) internal view returns (address) {
        uint256 tokenId = minted;
        uint256 seed = uint256(keccak256(abi.encodePacked(rng, tokenId)));
        if (seed % 10 != 0 || tokenId % 2 == uint256(dividendsPairStaking.getSoupedUp())) return parent; // 10% chance to steal if their faction is not winning
        // If it's minting a dog, chance for giga frog to steal. vice versa
        address thief =
            mucusFarm.randomGigaOrChad(seed, tokenId % 2 == 0 ? IMucusFarm.Faction.FROG : IMucusFarm.Faction.DOG);

        if (thief == address(0x0)) return parent;
        return thief;
    }

    function _isCorrectTypes(uint256[] calldata tokenIds, Faction transformationType) internal pure returns (bool) {
        for (uint256 i; i < tokenIds.length; i++) {
            if (tokenIds[i] % 2 != uint256(transformationType)) return false;
        }

        return true;
    }

    function setMucusFarm(address _mucusFarm) external onlyOwner {
        mucusFarm = IMucusFarm(_mucusFarm);
    }

    function withdraw() external onlyOwner {
        (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
        require(success, "Failed to send ETH");
    }

    function setPaidTokens(uint256 _paidTokens) external onlyOwner {
        tokensPaidInEth = _paidTokens;
    }

    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    function setPublicMintStarted() external onlyOwner {
        publicMintStarted = true;
    }

    function setBaseURI(string memory uri) external onlyOwner {
        baseURI = uri;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
