// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.13;

import {IERC721Receiver} from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "openzeppelin-contracts/contracts/security/Pausable.sol";

contract SwampAndYard is Ownable, IERC721Receiver, Pausable {
    // struct to store a stake's token, owner, and earning values
    struct Stake {
        uint16 tokenId;
        uint80 value;
        address owner;
    }

    event TokenStaked(address owner, uint256 tokenId, uint256 value);
    event SheepClaimed(uint256 tokenId, uint256 earned, bool unstaked);
    event WolfClaimed(uint256 tokenId, uint256 earned, bool unstaked);

    // maps tokenId to stake
    mapping(uint256 => Stake) public swamp;
    mapping(uint256 => Stake) public yard;

    // any rewards distributed when no wolves are staked
    uint256 public unparentedRewards = 0;

    // sheep earn 10000 $MUCUS per day
    uint256 public constant DAILY_MUCUS_RATE = 10000 * 1e18;
    // sheep must have 2 days worth of $MUCUS to unstake or else it's too cold
    uint256 public constant MINIMUM_TO_EXIT = 2 days;
    // wolves take a 20% tax on all $MUCUS claimed
    uint256 public constant mucus_CLAIM_TAX_PERCENTAGE = 20;
    // there will only ever be (roughly) 2.4 billion $MUCUS earned through staking
    uint256 public constant MAXIMUM_GLOBAL_mucus = 6262 * 1e8 * 1e18;

    // amount of $MUCUS earned so far
    uint256 public totalmucusEarned;
    // number of Dogs staked in the Yard
    uint256 public totalDogsStaked;
    // number of Frogs staked in the Swamp
    uint256 public totalFrogsStaked;
    // the last time $MUCUS was claimed
    uint256 public lastClaimTimestamp;

    // emergency rescue to allow unstaking without any checks but without $MUCUS
    bool public rescueEnabled = false;

    /**
     * @param _frogsAndDogs reference to the frogsAndDogs NFT contract
     * @param _mucus reference to the $MUCUS token
     */
    constructor(address _frogsAndDogs, address _mucus) {
        frogsAndDogs = frogsAndDogs(_frogsAndDogs);
        mucus = mucus(_mucus);
    }

    /**
     * adds Sheep and Wolves to the Barn and Pack
     * @param parent the address of the staker
     * @param tokenIds the IDs of the Sheep and Wolves to stake
     */
    function addManyToNaturalHabitat(address parent, uint16[] calldata tokenIds) external {
        require(
            parent == _msgSender() || _msgSender() == address(frogsAndDogs),
            "Cannot stake dogs or frogs that are not yours"
        );
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (_msgSender() != address(frogsAndDogs)) {
                // dont do this step if its a mint + stake
                require(frogsAndDogs.ownerOf(tokenIds[i]) == _msgSender(), "Not the owner of the frog or dog");
                frogsAndDogs.transferFrom(_msgSender(), address(this), tokenIds[i]);
            } else if (tokenIds[i] == 0) {
                continue; // there may be gaps in the array for stolen tokens
            }

            _addToNaturalHabitat(parent, tokenIds[i]);
        }
    }

    // TODO: need to create contract for gigasAndChads
    // staking a giga or chad gives them the ability to steal and tax
    function addManyToWreakHavok(uint16[] calldata tokenIds) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(_msgSender() == gigasAndChads.ownerOf(tokenIds[i]), "Not the owner of the giga or chad");
        }
    }

    /**
     * adds a Dog or Frog in the Yard or Swamp respectively
     * @param parent the address of the staker
     * @param tokenId the ID of the dog or frog to add to their habitat
     */
    function _addToNaturalHabitat(address parent, uint256 tokenId) internal whenNotPaused _updateEarnings {
        if (tokenId % 2 == 0) {
            yard[tokenId] = Stake({owner: parent, tokenId: uint16(tokenId), value: uint80(block.timestamp)});
            totalDogsStaked += 1;
        } else {
            swamp[tokenId] = Stake({owner: parent, tokenId: uint16(tokenId), value: uint80(block.timestamp)});
            totalFrogsStaked += 1;
        }

        emit TokenStaked(parent, tokenId, block.timestamp);
    }

    /**
     * adds a single GigaFrog or ChadDog in the Yard or Swamp respectively
     * @param parent the address of the staker
     * @param tokenId the ID of the Wolf to add to the Pack
     */
    function _addToWreakHavok(address parent, uint256 tokenId) internal {
        // implement chad and giga stuff here
        emit TokenStaked(parent, tokenId, mucusPerAlpha);
    }

    /**
     * CLAIMING / UNSTAKING
     */

    /**
     * realize $MUCUS earnings and optionally unstake tokens from the Barn / Pack
     * to unstake a Sheep it will require it has 2 days worth of $MUCUS unclaimed
     * @param tokenIds the IDs of the tokens to claim earnings from
     * @param unstake whether or not to unstake ALL of the tokens listed in tokenIds
     */
    function claimManyFromBarnAndPack(uint16[] calldata tokenIds, bool unstake)
        external
        whenNotPaused
        _updateEarnings
    {
        uint256 owed = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            owed += _claimFrogOrDog(tokenIds[i], unstake);
        }
        if (owed == 0) return;
        mucus.mint(_msgSender(), owed);
    }

    /**
     * realize $MUCUS earnings for a single Sheep and optionally unstake it
     * if not unstaking, pay a 20% tax to the staked Wolves
     * if unstaking, there is a 50% chance all $MUCUS is stolen
     * @param tokenId the ID of the Sheep to claim earnings from
     * @param unstake whether or not to unstake the Sheep
     * @return owed - the amount of $MUCUS earned
     */
    function _claimFrogOrDog(uint256 tokenId, bool unstake) internal returns (uint256 owed) {
        Stake memory stake = tokenId % 2 == 0 ? yard[tokenId] : swamp[tokenId];
        require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
        require(!(unstake && block.timestamp - stake.value < MINIMUM_TO_EXIT), "GONNA BE COLD WITHOUT TWO DAY'S mucus");
        if (totalmucusEarned < MAXIMUM_GLOBAL_mucus) {
            owed = (block.timestamp - stake.value) * DAILY_MUCUS_RATE / 1 days;
        } else if (stake.value > lastClaimTimestamp) {
            owed = 0; // $MUCUS production stopped already
        } else {
            owed = (lastClaimTimestamp - stake.value) * DAILY_MUCUS_RATE / 1 days; // stop earning additional $MUCUS if it's all been earned
        }
        if (unstake) {
            frogsAndDogs.safeTransferFrom(address(this), _msgSender(), tokenId, ""); // send back Sheep
            delete barn[tokenId];
            totalDogsStaked -= 1;
        } else {
            _payWolfTax(owed * mucus_CLAIM_TAX_PERCENTAGE / 100); // percentage tax to staked wolves
            owed = owed * (100 - mucus_CLAIM_TAX_PERCENTAGE) / 100; // remainder goes to Sheep owner
            barn[tokenId] = Stake({owner: _msgSender(), tokenId: uint16(tokenId), value: uint80(block.timestamp)}); // reset stake
        }
        emit SheepClaimed(tokenId, owed, unstake);
    }

    /**
     * realize $MUCUS earnings for a single Wolf and optionally unstake it
     * Wolves earn $MUCUS proportional to their Alpha rank
     * @param tokenId the ID of the Wolf to claim earnings from
     * @param unstake whether or not to unstake the Wolf
     * @return owed - the amount of $MUCUS earned
     */
    function _claimGigaOrFrogFromOpposingHabitat(uint256 tokenId, bool unstake) internal returns (uint256 owed) {
        require(gigasAndChads.ownerOf(tokenId) == address(this), "Cannot claim giga or chad that is not staked");
        require(gigasAndChadsDominating[_msgSender()].owner == _msgSender(), "You are not the owner of this giga or chad");

        uint256 previousMucusPerAlpha = pack[tokenId].value;
        Stake memory stake = pack[tokenId];
        owed = mucusPerAlpha - previousMucusPerAlpha; // Calculate portion of tokens based on Alpha

        if (unstake) {
            frogsAndDogs.safeTransferFrom(address(this), _msgSender(), tokenId, ""); // Send back Wolf
            delete pack[tokenId]; // Delete old mapping
        } else {
            pack[alpha][packIndices[tokenId]] =
                Stake({owner: _msgSender(), tokenId: uint16(tokenId), value: uint80(mucusPerAlpha)}); // reset stake
        }
        emit WolfClaimed(tokenId, owed, unstake);
    }

    /**
     * emergency unstake tokens
     * @param tokenIds the IDs of the tokens to claim earnings from
     */
    function rescue(uint256[] calldata tokenIds) external {
        require(rescueEnabled, "RESCUE DISABLED");
        uint256 tokenId;
        Stake memory stake;
        Stake memory lastStake;
        uint256 alpha;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            if (isSheep(tokenId)) {
                stake = barn[tokenId];
                require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
                frogsAndDogs.safeTransferFrom(address(this), _msgSender(), tokenId, ""); // send back Sheep
                delete barn[tokenId];
                totalDogsStaked -= 1;
                emit SheepClaimed(tokenId, 0, true);
            } else {
                alpha = _alphaForWolf(tokenId);
                stake = pack[alpha][packIndices[tokenId]];
                require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
                totalAlphaStaked -= alpha; // Remove Alpha from total staked
                frogsAndDogs.safeTransferFrom(address(this), _msgSender(), tokenId, ""); // Send back Wolf
                lastStake = pack[alpha][pack[alpha].length - 1];
                pack[alpha][packIndices[tokenId]] = lastStake; // Shuffle last Wolf to current position
                packIndices[lastStake.tokenId] = packIndices[tokenId];
                pack[alpha].pop(); // Remove duplicate
                delete packIndices[tokenId]; // Delete old mapping
                emit WolfClaimed(tokenId, 0, true);
            }
        }
    }

    /**
     * parentING
     */

    /**
     * add $MUCUS to claimable pot for the Pack
     * @param amount $MUCUS to add to the pot
     */
    function _payWolfTax(uint256 amount) internal {
        if (totalAlphaStaked == 0) {
            // if there's no staked wolves
            unparentedRewards += amount; // keep track of $MUCUS due to wolves
            return;
        }
        // makes sure to include any unparented $MUCUS
        mucusPerAlpha += (amount + unparentedRewards) / totalAlphaStaked;
        unparentedRewards = 0;
    }

    /**
     * tracks $MUCUS earnings to ensure it stops once 2.4 billion is eclipsed
     */
    modifier _updateEarnings() {
        if (totalmucusEarned < MAXIMUM_GLOBAL_mucus) {
            totalmucusEarned += (block.timestamp - lastClaimTimestamp) * totalDogsStaked * DAILY_MUCUS_RATE / 1 days;
            lastClaimTimestamp = block.timestamp;
        }
        _;
    }

    /**
     * ADMIN
     */

    /**
     * allows owner to enable "rescue mode"
     * simplifies parenting, prioritizes tokens out in emergency
     */
    function setRescueEnabled(bool _enabled) external onlyOwner {
        rescueEnabled = _enabled;
    }

    /**
     * enables owner to pause / unpause minting
     */
    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    /**
     * READ ONLY
     */

    /**
     * chooses a random Giga Frog to steal the newly bred dog
     * @param seed a random value from chainlinkVrf to choose a gigaFrog
     * @return gigaFrogOwner owner of the randomly selected gigaFrog thief
     */
    function randomGigaFrogOwner(uint256 seed) external view returns (address gigaFrogOwner) {
        if (totalGigaFrogsStaked == 0) return address(0x0);

        uint256 gigaFrogOwnerIndex = seed % totalGigaFrogsStaked;
        gigaFrogOwner = gigaFrogsStaked[gigaFrogOwnerIndex];

        return gigaFrogOwner;
    }

    /**
     * chooses a random Chad Dog to steal the newly bred frog
     * @param seed a random value from chainlinkVrf to choose a chadDog
     * @return chadDogOwner owner of the randomly selected chadDog thief
     */
    function randomChadDogOwner(uint256 seed) external view returns (address chadDogOwner) {
        if (totalChadDogsStaked == 0) return address(0x0);

        uint256 chadDogOwnerIndex = seed % totalChadDogsStaked;
        chadDogOwner = chadDogsStaked[chadDogOwnerIndex];

        return chadDogOwner;
    }

    function onERC721Received(address, address from, uint256, bytes calldata) external pure override returns (bytes4) {
        require(from == address(0x0), "Cannot send tokens to habitat directly");
        return IERC721Receiver.onERC721Received.selector;
    }
}
