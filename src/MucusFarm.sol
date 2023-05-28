pragma solidity ^0.8.13;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {IMucus} from "./IMucus";
import {ILPStaking} from "./ILPStaking";

contract MucusFarm {
    using SafeMath for uint256;

    uint256 public constant INITIAL_GIGA_CHAD_TOKEN_ID = 6000;
    uint256 public constant WINNING_POOL_TAX_RATE = 5;
    uint256 public constant LOSING_POOL_TAX_RATE = 20;
    uint256 public constant DAILY_MUCUS_RATE = 10000 * 1e18;
    uint256 public constant STOLEN_TOKEN_ID = 9393;

    enum Faction {
        FROG,
        DOG
    }

    struct Stake {
        address owner;
        uint256 previousClaimTimestamp; // for the case of a giga or a chad, needs to take either the preivousClaimTimestamp or the lastSoupCycle, whichever is bigger is what's subbed
        uint256 previousTaxPer;
        uint256 previousSoupIndex;
    }

    mapping(uint256 => Stake) public frogsAndDogsStaked;
    uint256 public totalMucusClaimed;
    uint256 public taxPerGiga;
    uint256 public taxPerChad;
    uint256[] gigasStaked;
    uint256[] chadsStaked;

    IERC721 public frogsAndDogs;
    IERC20 public mucus;
    ILPStaking public lpStaking;

    event TokenStaked(address parent, uint256 tokenId);
    event TokenUnstaked(address parent, uint256 tokenId);

    constructor(address _frogsAndDogs, address _mucus, address _lpStaking) {
        frogsAndDogs = IERC20(frogsAndDogs);
        mucus = IMucus(_mucus);
        lpStaking = ILPStaking(_lpStaking);
    }

    function addManyToMucusFarm(address parent, uint256[] tokenIds) external {
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

            if (isFrog(tokenIds[i])) {
                frogsAndDogsStaked[tokenIds[i]] = Stake({
                    owner: parent,
                    faction: Faction.FROG,
                    previousTaxPer: taxPerGiga,
                    previousClaimTimetamp: block.timestamp,
                    previousSoupIndex: LPStaking.currentSoupIndex()
                });
                if (tokenIds[i] >= INITIAL_GIGA_CHAD_TOKEN_ID) gigasStaked.push(tokenIds[i]);
            } else {
                frogsAndDogsStaked[tokenIds[i]] = Stake({
                    owner: parent,
                    faction: Faction.DOG,
                    previousTaxPer: taxPerChad,
                    previousClaimTimetamp: block.timestamp,
                    previousSoupIndex: LPStaking.currentSoupIndex()
                });
                if (tokenIds[i] >= INITIAL_GIGA_CHAD_TOKEN_ID) chadsStaked.push(tokenIds[i]);
            }

            emit TokenStaked(parent, tokenIds[i]);
        }
    }

    // TEST CASES:
    function claimMany(uint256[] tokenIds, bool unstake) external {
        uint256 totalMucusClaimed;
        uint256 totalBurnableTax;
        uint256 totalClaimableTax;
        for (uint256 i; i < tokenIds.length; i++) {
            Stake memory stake = frogsAndDogsStaked[tokenIds[i]];
            require(stake.owner == _msgSender(), "Cannot claim rewards for frog or dog that you didn't stake");
            if (tokenIds[i] < INITIAL_GIGA_CHAD_TOKEN_ID) {
                totalMucusClaimed = (block.timestamp - stake.previousClaimTimestamp).mul(DAILY_MUCUS_RATE).div(1 days);
                (uint256 burnableTax, uint256 claimableTax) = _payTax(tokenIds[i]);
                totalBurnableTax += burnableTax;
                totalClaimableTax += claimableTax;
                total.previousClaimTimestamp = block.timestamp;
            } else {
                if (isFrog(tokenIds[i])) {
                    totalMucusClaimed += taxPerGiga - stake.previousTaxPer;
                    stake.previousTaxPer = taxPerGiga;
                } else {
                    totalMucusClaimed += taxPerChad - stake.previousTaxPer;
                    stake.previousTaxPer = taxPerChad;
                }
            }

            stake.previousSoupIndex = LPStaking.currentSoupIndex();
            frogsAndDogsStaked[tokenIds[i]] = stake;

            if (unstake) {
                frogsAndDogs.transfer(_msgSender, tokenIds[i]);
                if (tokenIds[i] >= INITIAL_GIGA_CHAD_TOKEN_ID) {
                    // implement popping for giga and chad
                }
            }
        }

        mucus.transfer(_msgSender(), totalMucusClaimed);
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
    function _payTax(uint256 tokenId) internal view returns (uint256 burnableTax, uint256 claimableTax) {
        Stake storage stake = frogsAndDogsStaked[tokenId];
        (
            uint256 currentSoupIndex,
            uint256 soupCycleDuration,
            LPStaking.SoupCycle calldata previousSoupCycle,
            LPStaking.SoupCycle calldata currentSoupCycle
        ) = lpStaking.getSoup(stake.previousSoupIndex);

        // if the previous soup index is the same as the current one, then the next cycle hasn't passed yet
        // so there is no previous cycles to claim
        if (stake.previousSoupIndex < currentSoupIndex) {
            // previous leftover
            // extra layer of safety since the soup cycles are triggered manually either by a trade or by the owner
            // so it's possible for the previousClaimTimestamp to be after the previousSoupCycle timestamp plus the soupCycleDuration if its close enough
            if (previousSoupCycle.timestamp + soupCycleDuration > stake.previousClaimTimestamp) {
                if (isFrog(tokenId) == previousSoupCycle.soupedUp) {
                    burnableTax += ((previousSoupCycle.timestamp + soupCycleDuration) - stake.previousClaimTimestamp)
                        .mul(DAILY_MUCUS_RATE).mul(5).div(100).div(1 days);
                } else {
                    claimableTax += ((previousSoupCycle.timestamp + soupCycleDuration) - stake.previousClaimTimestamp)
                        .mul(DAILY_MUCUS_RATE).mul(20).div(100).div(1 days);
                }
            }

            // cycles passed
            // -1 to account for the previous leftover cycle and if the previous recorded cycle was a frog cycle
            uint256 soupCyclesPassed = currentSoupIndex - stake.previousSoupIndex - 1;
            uint256 totalFrogWinsPassed =
                currentSoupCycle.totalFrogWins - previousSoupCycle.totalFrogWins - previousSoupCycle.soupedUp; // If the previous leftover cycle was a frog cycle, don't count it again
            uint256 totalDogWinsPassed = soupCyclesPassed - totalFrogWinsPassed;
            if (isFrog(tokenId)) {
                claimableTax += totalDogWinsPassed.mul(DAILY_MUCUS_RATE).mul(soupCycleDuration).mul(20).div(100);
                burnableTax += totalFrogWinsPassed.mul(DAILY_MUCUS_RATE).mul(soupCycleDuration).mul(5).div(100);
            } else {
                claimableTax += totalFrogWinsPassed.mul(DAILY_MUCUS_RATE).mul(soupCycleDuration).mul(20).div(100);
                burnableTax += totalDogWinsPassed.mul(DAILY_MUCUS_RATE).mul(soupCycleDuration).mul(5).div(100);
            }
        }

        // current leftover
        // to cover the case when the user claims twice in one cycle
        uint256 previousTimestamp = currentSoupCycle.timestamp > stake.previousClaimTimestamp
            ? currentSoupCycle.timestamp
            : stake.previousClaimTimestamp;
        if (isFrog(tokenId) == currentSoupCycle.soupedUp) {
            burnableTax += (block.timestamp - previousTimestamp).mul(DAILY_MUCUS_RATE).mul(5).div(100).div(1 days);
        } else {
            claimableTax += (block.timestamp - previousTimestamp).mul(DAILY_MUCUS_RATE).mul(20).div(100).div(1 days);
        }

        return (burableTax, claimableTax);
    }

    function isFrog(uint256 tokenId) internal pure returns (uint256) {
        return tokenId % 2;
    }
}
