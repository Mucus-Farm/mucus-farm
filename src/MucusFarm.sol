// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {Context} from "openzeppelin-contracts/contracts/utils/Context.sol";
import {IMucusFarm} from "./interfaces/IMucusFarm.sol";
import {IMucus} from "./interfaces/IMucus.sol";
import {IDividendsPairStaking} from "./interfaces/IDividendsPairStaking.sol";

contract MucusFarm is IMucusFarm, IERC721Receiver, Context {
    uint256 public constant INITIAL_GIGA_CHAD_TOKEN_ID = 6000;
    uint256 public constant WINNING_POOL_TAX_RATE = 5;
    uint256 public constant LOSING_POOL_TAX_RATE = 20;
    uint256 public constant DAILY_MUCUS_RATE = 10000 * 1e18;
    uint256 public constant MAX_MUCUS_MINTED = 6262 * 1e8 * 1e18;
    address private _DEAD = 0x000000000000000000000000000000000000dEaD;
    address private _owner;
    bool public rescueEnabled;
    bool public paused;

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
        _owner = _msgSender();
    }

    modifier onlyOwner() {
        require(_msgSender() == _owner);
        _;
    }

    modifier notPaused() {
        require(!paused);
        _;
    }

    function addManyToMucusFarm(address parent, uint256[] calldata tokenIds) external notPaused {
        require(
            _msgSender() == parent || _msgSender() == address(frogsAndDogs),
            "sender must be the parent or the frogs and dogs contract"
        );

        // safe to use tokenId 0 since it's being minted to the team
        for (uint256 i; i < tokenIds.length; i++) {
            if (_msgSender() != address(frogsAndDogs)) {
                frogsAndDogs.transferFrom(_msgSender(), address(this), tokenIds[i]);
            } else if (tokenIds[i] == 9393) {
                continue;
            }

            if (_isFrog(tokenIds[i])) {
                addToMucusFarm(parent, tokenIds[i], taxPerGiga, gigasStaked);
            } else {
                addToMucusFarm(parent, tokenIds[i], taxPerChad, chadsStaked);
            }
        }

        emit TokensStaked(parent, tokenIds);
    }

    function addToMucusFarm(address parent, uint256 tokenId, uint256 taxPer, uint256[] storage staked) internal {
        farm[tokenId] = Stake({
            owner: parent,
            lockingEndTime: block.timestamp + 3 days,
            previousClaimTimestamp: block.timestamp,
            previousTaxPer: taxPer,
            previousSoupIndex: dividendsPairStaking.currentSoupIndex(),
            gigaChadIndex: staked.length
        });
        if (tokenId >= INITIAL_GIGA_CHAD_TOKEN_ID) staked.push(tokenId);
    }

    function parseEther(uint256 amount) internal pure returns (uint256) {
        return amount / 1 ether;
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
    function claimMany(uint256[] calldata tokenIds, bool unstake) external notPaused {
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
            totalMucusEarned += (block.timestamp - stake.previousClaimTimestamp) * mucusRate / 1 days;
            (uint256 burnableTax, uint256 claimableTax) = _getTax(tokenIds[i]);
            if (_isFrog(tokenIds[i])) totalClaimableChadTax += claimableTax;
            else totalClaimableGigaTax += claimableTax;
            totalBurnableTax += burnableTax;
            totalMucusEarned -= (claimableTax + burnableTax);
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
                require(block.timestamp >= stake.lockingEndTime, "Cannot unstake frogs or dogs that are still locked");
                removeFromMucusFarm(tokenIds[i], stake, _isFrog(tokenIds[i]) ? gigasStaked : chadsStaked);
            }
        }

        // update giga and chads tax per
        if (chadsStaked.length == 0) {
            unclaimedChadTax += totalClaimableChadTax;
        } else {
            taxPerChad += (totalClaimableChadTax + unclaimedChadTax) / chadsStaked.length;
            if (unclaimedChadTax > 0) unclaimedChadTax = 0;
        }
        if (gigasStaked.length == 0) {
            unclaimedGigaTax += totalClaimableGigaTax;
        } else {
            taxPerGiga += (totalClaimableGigaTax + unclaimedGigaTax) / gigasStaked.length;
            if (unclaimedGigaTax > 0) unclaimedGigaTax = 0;
        }

        // mint mucus
        mintMucus(_msgSender(), totalMucusEarned);
        mintMucus(_DEAD, totalBurnableTax);

        emit TokensFarmed(_msgSender(), totalMucusEarned, tokenIds);
        if (unstake) emit TokensUnstaked(_msgSender(), tokenIds);
    }

    function removeFromMucusFarm(uint256 tokenId, Stake memory stake, uint256[] storage stakedTokenIds) internal {
        if (tokenId >= INITIAL_GIGA_CHAD_TOKEN_ID) {
            uint256 lastStakedTokenId = stakedTokenIds[stakedTokenIds.length - 1];
            Stake storage lastStaked = farm[lastStakedTokenId];

            stakedTokenIds[stake.gigaChadIndex] = lastStakedTokenId; // Shuffle last giga or chad to current position
            lastStaked.gigaChadIndex = stake.gigaChadIndex;
            stakedTokenIds.pop(); // Remove duplicate
        }
        delete farm[tokenId]; // Delete old mapping
        frogsAndDogs.transferFrom(address(this), _msgSender(), tokenId); // transfer the frog or dog back to owner
    }

    function mintMucus(address to, uint256 amount) internal {
        if (amount > 0 && totalMucusMinted < MAX_MUCUS_MINTED) {
            uint256 mucusMinted =
                totalMucusMinted + amount > MAX_MUCUS_MINTED ? MAX_MUCUS_MINTED - totalMucusMinted : amount;
            totalMucusMinted += mucusMinted;
            mucus.mint(to, mucusMinted);
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
        Stake memory stake = farm[tokenId];
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
                    burnableTax += taxRate(
                        (previousSoupCycle.timestamp + soupCycleDuration) - stake.previousClaimTimestamp, mucusRate, 5
                    );
                } else {
                    claimableTax += taxRate(
                        (previousSoupCycle.timestamp + soupCycleDuration) - stake.previousClaimTimestamp, mucusRate, 20
                    );
                }
            }

            // cycles passed
            // -1 to account for the previous leftover cycle
            uint256 soupCyclesPassed = currentSoupIndex - stake.previousSoupIndex - 1;
            uint256 totalFrogWinsPassed =
                currentSoupCycle.totalFrogWins - previousSoupCycle.totalFrogWins - uint256(currentSoupCycle.soupedUp); // If the current cycle is a frog cycle, don't count it
            uint256 totalDogWinsPassed = soupCyclesPassed - totalFrogWinsPassed;
            if (_isFrog(tokenId)) {
                claimableTax += taxRate(totalDogWinsPassed * soupCycleDuration, mucusRate, 20);
                burnableTax += taxRate(totalFrogWinsPassed * soupCycleDuration, mucusRate, 5);
            } else {
                claimableTax += taxRate(totalFrogWinsPassed * soupCycleDuration, mucusRate, 20);
                burnableTax += taxRate(totalDogWinsPassed * soupCycleDuration, mucusRate, 5);
            }
        }

        // current leftover
        // to cover the case when the user claims twice in one cycle
        uint256 previousTimestamp = currentSoupCycle.timestamp > stake.previousClaimTimestamp
            ? currentSoupCycle.timestamp
            : stake.previousClaimTimestamp;
        if (toUInt256(_isFrog(tokenId)) == uint256(currentSoupCycle.soupedUp)) {
            burnableTax += taxRate(block.timestamp - previousTimestamp, mucusRate, 5);
        } else {
            claimableTax += taxRate(block.timestamp - previousTimestamp, mucusRate, 20);
        }

        return (burnableTax, claimableTax);
    }

    function taxRate(uint256 duration, uint256 mucusRate, uint256 taxPercentage) internal pure returns (uint256 rate) {
        assembly {
            rate := div(div(mul(mul(duration, mucusRate), taxPercentage), 100), 86400)
        }
    }

    function randomGigaOrChad(uint256 seed, Faction faction) external view returns (address) {
        uint256 tokenId;
        if (faction == Faction.FROG && gigasStaked.length == 0) {
            return address(0x0);
        } else if (faction == Faction.DOG && chadsStaked.length == 0) {
            return address(0x0);
        }

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
            require(farm[tokenId].owner == _msgSender(), "Cannot rescue frogs or dogs that you didn't stake");
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
        paused = _paused;
    }

    function onERC721Received(address, address from, uint256, bytes calldata) external pure override returns (bytes4) {
        require(from == address(0x0), "Cannot send frogs or dogs directly to the MucusFarm");
        return IERC721Receiver.onERC721Received.selector;
    }
}
