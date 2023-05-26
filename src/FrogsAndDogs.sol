// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.13;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/contracts/security/Pausable.sol";

contract FrogsAndDogs is ERC721, Ownable, Pausable {
    uint256 public constant MINT_PRICE = 0.06942 ether;
    uint256 public immutable MAX_SUPPLY = 9393;
    uint256 public tokensPaidInEth = MAX_SUPPLY / 5; // 20% of the supply
    uint16 public minted;

    constructor() ERC721("Frogs and Dogs", "FND") {}

    /**
     * mint a token - 90% Sheep, 10% Wolves
     * The first 20% are free to claim, the remaining cost $WOOL
     */
    function mint(uint256 amount, bool stake) external payable {
        require(minted + amount <= MAX_SUPPLY, "All tokens minted");
        require(amount > 0 && amount <= 10, "Invalid mint amount");
        if (minted < tokensPaidInEth) {
            require(minted + amount <= tokensPaidInEth, "All tokens on-sale already sold");
            require(amount * MINT_PRICE == msg.value, "Invalid payment amount");
        } else {
            require(msg.value == 0, "Mint requires MUCUS");
        }

        uint256 totalMucusCost = 0;
        uint16[] memory tokenIds = stake ? new uint16[](amount) : new uint16[](0);
        uint256 seed;
        for (uint256 i = 0; i < amount; i++) {
            minted++;
            seed = random(minted);
            address recipient = selectRecipient(seed);

            if (!stake || recipient != _msgSender()) {
                _safeMint(recipient, minted);
            } else {
                _safeMint(address(swampAndYard), minted);
                tokenIds[i] = minted;
            }
            totalMucusCost += mintCost(minted);
        }

        if (totalMucusCost > 0) mucus.burn(_msgSender(), totalMucusCost);
        if (stake) swampAndYard.addManyToBarnAndPack(_msgSender(), tokenIds);
    }

    /**
     * the first 20% are paid in ETH
     * the next 20% are 20000 $MUCUS
     * the next 40% are 40000 $MUCUS
     * the final 20% are 80000 $MUCUS
     * @param tokenId the ID to check the cost of to mint
     * @return the cost of the given token ID
     */
    function mintCost(uint256 tokenId) public view returns (uint256) {
        if (tokenId <= tokensPaidInEth) return 0;
        if (tokenId <= MAX_SUPPLY * 2 / 5) return 20000 ether;
        if (tokenId <= MAX_SUPPLY * 4 / 5) return 40000 ether;
        return 80000 ether;
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
     * @param seed a random value to select a recipient from
     * @return the address of the recipient (either the minter or the Wolf thief's owner)
     */
    function selectRecipient(uint256 chinlinkRng) internal view returns (address) {
        if (minted <= tokensPaidInEth || ((chainLinkRng >> 245) % 10) != 0) return _msgSender(); // top 10 bits haven't been used
        uint256 seed = uint256(keccak256(abi.encodePacked(chinlinkRng, minted)));
        // If it's minting a dog, chance for giga frog to steal. vice versa
        address thief;
        if (minted % 2 == 0) {
            swampAndYards.randomGigaFrogOwner(seed);
        } else {
            swampAndYards.randomChadDogOwner(seed);
        }
        if (thief == address(0x0)) return _msgSender();
        return thief;
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

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return traits.tokenURI(tokenId);
    }
}
