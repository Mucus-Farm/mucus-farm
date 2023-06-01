// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {Pausable} from "openzeppelin-contracts/contracts/security/Pausable.sol";
import {IMucusFarm} from "./interfaces/IMucusFarm.sol";
import {IMucus} from "./interfaces/IMucus.sol";
import {IDividendsPairStaking} from "./interfaces/IDividendsPairStaking.sol";

contract MucusFarm is IMucusFarm, IERC721Receiver, Pausable {
    uint256 public constant INITIAL_GIGA_CHAD_TOKEN_ID = 6000;
    uint256 public constant WINNING_POOL_TAX_RATE = 5;
    uint256 public constant LOSING_POOL_TAX_RATE = 20;
    uint256 public constant DAILY_MUCUS_RATE = 10000 * 1e18;
    uint256 public constant STOLEN_TOKEN_ID = 9393;
    uint256 public constant MAX_MUCUS_MINTED = 6262 * 1e8 * 1e18;
    address private _DEAD = 0x000000000000000000000000000000000000dEaD;
    address private _owner;
    bool public rescueEnabled;

    mapping(uint256 => Stake) public farm;
    uint256 public totalMucusMinted;
    uint256 public taxPerGiga;
    uint256 public taxPerChad;
    uint256 public unclaimedGigaTax;
    uint256 public unclaimedChadTax;
    uint256[] public gigasStaked;
    uint256[] public chadsStaked;

    IERC721 public frogsAndDogs;
    IMucus public mucus;
    IDividendsPairStaking public dividendsPairStaking;

    constructor(address _frogsAndDogs, address _mucus, address _dividendsPairStaking) {
        frogsAndDogs = IERC721(_frogsAndDogs);
        mucus = IMucus(_mucus);
        dividendsPairStaking = IDividendsPairStaking(_dividendsPairStaking);
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
    }

    function addManyToMucusFarm(address parent, uint256[] calldata tokenIds) external {
        require(
            _msgSender() == parent || _msgSender() == address(frogsAndDogs),
            "Cannot stake frogs or dogs that you don't own"
        );

        for (uint256 i; i < tokenIds.length; i++) {
            if (_msgSender() != address(frogsAndDogs)) {
                require(
                    frogsAndDogs.ownerOf(tokenIds[i]) == _msgSender(), "Cannot stake frogs or dogs that you don't own"
                );
                frogsAndDogs.transferFrom(_msgSender(), address(this), tokenIds[i]);
            } else if (tokenIds[i] == STOLEN_TOKEN_ID) {
                continue;
            }

            if (_isFrog(tokenIds[i])) {
                addToMucusFarm(parent, tokenIds[i], taxPerGiga, gigasStaked);
            } else {
                addToMucusFarm(parent, tokenIds[i], taxPerChad, chadsStaked);
            }

            emit TokenStaked(parent, tokenIds[i]);
        }
    }

    function addToMucusFarm(address parent, uint256 tokenId, uint256 taxPer, uint256[] storage staked) internal {
        farm[tokenId] = Stake({
            owner: parent,
            lockingEndtime: block.timestamp + 3 days,
            previousTaxPer: taxPer,
            previousClaimTimestamp: block.timestamp,
            previousSoupIndex: dividendsPairStaking.currentSoupIndex(),
            gigaOrChadIndex: staked.length
        });
        if (tokenId >= INITIAL_GIGA_CHAD_TOKEN_ID) staked.push(tokenId);
    }

    // Test case 1: claim sheep and not unstake
    // Test case 2: claim sheep and unstake
    // Test case 3: claim wolf and not unstake
    // Test case 4: claim wolf and unstake
    // Test case 5: claim sheep then wolf and not unstake
    // Test case 6: claim sheep then wolf and unstake
    // Test case 7: claim wolf then sheep and not unstake
    // Test case 8: claim wolf then sheep and unstake
    // Test case 9: claim sheep when there is no wolves staked
    // User test case 9:
    //  - claim sheep when no wolves staked
    //  - stake wolf
    //  - claim sheep again
    //  - claim wolf
    // User test case 10:
    //   - claim sheep then wolf and unstake
    //   - stake wolf
    //   - claim sheep then wolf and not unstake unsta
    // User test case 10:
    // User test case
    // Be mindful of the taxPerGiga and taxPerChad rates. Make sure to add on to it after the sheep mucus claim, else wise
    // the claimer is essentially claiming from there own stack, which may have some weird consequences
    function claimMany(uint256[] calldata tokenIds, bool unstake) external {
        // farming accounting
        uint256 totalMucusEarned;
        uint256 totalBurnableTax;
        uint256 totalClaimableGigaTax;
        uint256 totalClaimableChadTax;

        // test to see if it does save on gas
        // // cache in memory to save on gas
        // uint256[] memory _gigasStaked = gigasStaked;
        // uint256[] memory _chadsStaked = chadsStaked;
        // uint256 _taxPerGiga = taxPerGiga;
        // uint256 _taxPerChad = taxPerChad;

        for (uint256 i; i < tokenIds.length; i++) {
            Stake memory stake = farm[tokenIds[i]];
            require(stake.owner == _msgSender(), "Cannot claim rewards for frog or dog that you didn't stake");

            // calculate earnings
            uint256 mucusRate = tokenIds[i] >= INITIAL_GIGA_CHAD_TOKEN_ID ? DAILY_MUCUS_RATE * 3 : DAILY_MUCUS_RATE;
            totalMucusEarned = (block.timestamp - stake.previousClaimTimestamp) * mucusRate / 1 days;
            (uint256 burnableTax, uint256 claimableTax) = _getTax(tokenIds[i]);
            if (_isFrog(tokenIds[i])) totalClaimableChadTax += claimableTax;
            else totalClaimableGigaTax += claimableTax;
            totalMucusEarned -= claimableTax - burnableTax;
            totalBurnableTax += burnableTax;
            if (tokenIds[i] >= INITIAL_GIGA_CHAD_TOKEN_ID) {
                totalMucusEarned += (_isFrog(tokenIds[i]) ? taxPerGiga : taxPerChad) - stake.previousTaxPer;
            }

            // update stake or unstake
            if (!unstake) {
                stake.previousClaimTimestamp = block.timestamp;
                stake.previousTaxPer = _isFrog(tokenIds[i]) ? taxPerGiga : taxPerChad;
                stake.previousSoupIndex = dividendsPairStaking.currentSoupIndex();
                farm[tokenIds[i]] = stake;
            } else {
                require(block.timestamp > stake.lockingEndtime, "Cannot unstake frogs or dogs that are still locked");
                removeFromMucusFarm(tokenIds[i], stake, _isFrog(tokenIds[i]) ? gigasStaked : chadsStaked);
            }

            emit TokenFarmed(tokenIds[i], totalMucusEarned);
        }

        // update giga and chads tax per
        if (chadsStaked.length == 0) {
            unclaimedChadTax += totalClaimableChadTax;
        } else {
            taxPerChad += (totalClaimableChadTax + unclaimedChadTax) / chadsStaked.length;
            unclaimedChadTax = 0;
        }
        if (gigasStaked.length == 0) {
            unclaimedGigaTax += totalClaimableGigaTax;
        } else {
            taxPerGiga += (totalClaimableGigaTax + unclaimedGigaTax) / gigasStaked.length;
            unclaimedGigaTax = 0;
        }

        // mint mucus
        mintMucus(_msgSender(), totalMucusEarned);
        mintMucus(_DEAD, totalBurnableTax);
    }

    function removeFromMucusFarm(uint256 tokenId, Stake memory stake, uint256[] storage stakedTokenIds) internal {
        require(stake.owner == _msgSender(), "Cannot unstake tokens that you don't own");
        if (tokenId >= INITIAL_GIGA_CHAD_TOKEN_ID) {
            uint256 lastStakedTokenId = stakedTokenIds[stakedTokenIds.length - 1];
            Stake storage lastStaked = farm[lastStakedTokenId];

            stakedTokenIds[stake.gigaOrChadIndex] = lastStakedTokenId; // Shuffle last giga or chad to current position
            lastStaked.gigaOrChadIndex = stake.gigaOrChadIndex;
            stakedTokenIds.pop(); // Remove duplicate
        }
        delete farm[tokenId]; // Delete old mapping
        frogsAndDogs.transferFrom(address(this), _msgSender(), tokenId); // transfer the frog or dog back to owner

        emit TokenUnstaked(_msgSender(), tokenId);
    }

    function mintMucus(address to, uint256 amount) internal {
        if (amount > 0 && totalMucusMinted < MAX_MUCUS_MINTED) {
            uint256 mucusToMint =
                totalMucusMinted + amount > MAX_MUCUS_MINTED ? MAX_MUCUS_MINTED - totalMucusMinted : amount;
            totalMucusMinted += mucusToMint;
            mucus.mint(to, mucusToMint);

            emit MucusEarned(to, mucusToMint);
        }
    }

    // TEST CASES:
    // Test 1: When the previous claim is in the middle of a cycle
    // Test 2: When the current claim is in the middle of a cycle
    // Test 3: When the previous soup index is the same as the current soup index (when they claim twice in the same cycle)
    // Test 4: The first claim is in the middle of the very first soup cycle
    // Test 5: The first claim is in the middle of a cycle that isn't the first cycle
    // A users previous claim could be in the middle of a soup cycle.
    // Similarly, their current claim could be in the middle of a soup cycle.
    // If either their previous claim was in the middle of the cycle, they haven't claimed the rewards for the rest of that cycle.
    // similarly, if their current claim is in the middle of a cycle, then they can only claim however much has passed for that
    // current cycle
    // This is just a bunch of off by one errors waiting to happen
    //
    // Cycle1                 Cycle2            Cycle3                Cycle4
    //   |----------------------|-----------------|---------------------|-------------|
    //                  |////////                  ///////////|
    //              Prev. Claim                           Curr. Claim
    function _getTax(uint256 tokenId) internal view returns (uint256 burnableTax, uint256 claimableTax) {
        Stake storage stake = farm[tokenId];
        uint256 mucusRate = tokenId >= INITIAL_GIGA_CHAD_TOKEN_ID ? DAILY_MUCUS_RATE * 3 : DAILY_MUCUS_RATE;
        (
            uint256 currentSoupIndex,
            uint256 soupCycleDuration,
            IDividendsPairStaking.SoupCycle memory previousSoupCycle,
            IDividendsPairStaking.SoupCycle memory currentSoupCycle
        ) = dividendsPairStaking.getSoup(stake.previousSoupIndex);

        // if the previous soup index is the same as the current one, then the next cycle hasn't passed yet
        // so there is no previous cycles to claim
        if (stake.previousSoupIndex < currentSoupIndex) {
            // previous leftover
            // extra layer of safety since the soup cycles are triggered manually either by a trade or by the owner
            // so it's possible for the previousClaimTimestamp to be after the previousSoupCycle timestamp plus the soupCycleDuration if its close enough
            if (previousSoupCycle.timestamp + soupCycleDuration > stake.previousClaimTimestamp) {
                if (toUInt256(_isFrog(tokenId)) == uint256(previousSoupCycle.soupedUp)) {
                    burnableTax += ((previousSoupCycle.timestamp + soupCycleDuration) - stake.previousClaimTimestamp)
                        * mucusRate * 5 / 100 / 1 days;
                } else {
                    claimableTax += ((previousSoupCycle.timestamp + soupCycleDuration) - stake.previousClaimTimestamp)
                        * mucusRate * 20 / 100 / 1 days;
                }
            }

            // cycles passed
            // -1 to account for the previous leftover cycle and if the previous recorded cycle was a frog cycle
            uint256 soupCyclesPassed = currentSoupIndex - stake.previousSoupIndex - 1;
            uint256 totalFrogWinsPassed =
                currentSoupCycle.totalFrogWins - previousSoupCycle.totalFrogWins - uint256(previousSoupCycle.soupedUp); // If the previous leftover cycle was a frog cycle, don't count it again
            uint256 totalDogWinsPassed = soupCyclesPassed - totalFrogWinsPassed;
            if (_isFrog(tokenId)) {
                claimableTax += totalDogWinsPassed * soupCycleDuration * mucusRate * 20 / 100 / 1 days;
                burnableTax += totalFrogWinsPassed * soupCycleDuration * mucusRate * 5 / 100 / 1 days;
            } else {
                claimableTax += totalFrogWinsPassed * soupCycleDuration * mucusRate * 20 / 100 / 1 days;
                burnableTax += totalDogWinsPassed * soupCycleDuration * mucusRate * 5 / 100 / 1 days;
            }
        }

        // current leftover
        // to cover the case when the user claims twice in one cycle
        uint256 previousTimestamp = currentSoupCycle.timestamp > stake.previousClaimTimestamp
            ? currentSoupCycle.timestamp
            : stake.previousClaimTimestamp;
        if (toUInt256(_isFrog(tokenId)) == uint256(currentSoupCycle.soupedUp)) {
            burnableTax += (block.timestamp - previousTimestamp) * mucusRate * 5 / 100 / 1 days;
        } else {
            claimableTax += (block.timestamp - previousTimestamp) * mucusRate * 20 / 100 / 1 days;
        }

        return (burnableTax, claimableTax);
    }

    function randomGigaOrChad(uint256 seed, Faction faction) external view returns (address) {
        uint256 tokenId;
        if (faction == Faction.FROG) {
            tokenId = gigasStaked[seed % gigasStaked.length];
        } else {
            tokenId = chadsStaked[seed % chadsStaked.length];
        }

        return farm[tokenId].owner;
    }

    function rescue(uint256[] calldata tokenIds) external {
        require(rescueEnabled, "Rescue mode not enabled");
        uint256 tokenId;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            removeFromMucusFarm(tokenId, farm[tokenId], _isFrog(tokenId) ? gigasStaked : chadsStaked);
        }
    }

    function _isFrog(uint256 tokenId) internal pure returns (bool) {
        return tokenId % 2 == 1;
    }

    function toUInt256(bool x) internal pure returns (uint256 r) {
        assembly {
            r := x
        }
    }

    function setRescueEnabled(bool _enabled) external onlyOwner {
        rescueEnabled = _enabled;
    }

    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    function onERC721Received(address, address from, uint256, bytes calldata) external pure override returns (bytes4) {
        require(from == address(0x0), "Cannot send frogs or dogs directly to the MucusFarm");
        return IERC721Receiver.onERC721Received.selector;
    }
}
