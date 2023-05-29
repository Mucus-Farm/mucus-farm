pragma solidity ^0.8.13;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {Pausable} from "openzeppelin-contracts/contracts/security/Pausable.sol";
import {IMucus} from "./IMucus";
import {ILPStaking} from "./ILPStaking";

contract MucusFarm is IERC721Receiver, Pausable {
    using SafeMath for uint256;

    uint256 public constant INITIAL_GIGA_CHAD_TOKEN_ID = 6000;
    uint256 public constant WINNING_POOL_TAX_RATE = 5;
    uint256 public constant LOSING_POOL_TAX_RATE = 20;
    uint256 public constant DAILY_MUCUS_RATE = 10000 * 1e18;
    uint256 public constant STOLEN_TOKEN_ID = 9393;
    uint256 public constant MAX_MUCUS_MINTED = 6262 * 1e8 * 1e18;
    address private DEAD = 0x000000000000000000000000000000000000dEaD;
    address private _owner;

    enum Faction {
        FROG,
        DOG
    }

    struct Stake {
        address owner;
        uint256 previousClaimTimestamp; // for the case of a giga or a chad, needs to take either the preivousClaimTimestamp or the lastSoupCycle, whichever is bigger is what's subbed
        uint256 previousTaxPer;
        uint256 previousSoupIndex;
        uint256 gigaOrChadIndex;
    }

    mapping(uint256 => Stake) public farm;
    uint256 public totalMucusMinted;
    uint256 public taxPerGiga;
    uint256 public taxPerChad;
    uint256 public unclaimedGigaTax;
    uint256 public unclaimedChadTax;
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
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
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
                farm[tokenIds[i]] = Stake({
                    owner: parent,
                    faction: Faction.FROG,
                    previousTaxPer: taxPerGiga,
                    previousClaimTimetamp: block.timestamp,
                    previousSoupIndex: LPStaking.currentSoupIndex()
                });
                if (tokenIds[i] >= INITIAL_GIGA_CHAD_TOKEN_ID) gigasStaked.push(tokenIds[i]);
            } else {
                farm[tokenIds[i]] = Stake({
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
    function claimMany(uint256[] tokenIds, bool unstake) external {
        uint256 totalMucusEarned;
        uint256 totalBurnableTax;
        uint256 totalClaimableGigaTax;
        uint256 totalClaimableChadTax;

        for (uint256 i; i < tokenIds.length; i++) {
            Stake memory stake = farm[tokenIds[i]];
            require(stake.owner == _msgSender(), "Cannot claim rewards for frog or dog that you didn't stake");

            // calculate earnings
            uint256 mucusRate = tokenIds[i] >= INITIAL_GIGA_CHAD_TOKEN_ID ? DAILY_MUCUS_RATE * 3 : DAILY_MUCUS_RATE;
            totalMucusEarned = (block.timestamp - stake.previousClaimTimestamp).mul(mucusRate).div(1 days);
            (uint256 burnableTax, uint256 claimableTax) = _getTax(tokenIds[i]);
            if (isFrog(tokenIds[i])) totalClaimableChadTax += claimableTax;
            else totalClaimableGigaTax += claimableTax;
            totalMucusEarned -= claimableTax - burnableTax;
            totalBurnableTax += burnableTax;
            if (tokenIds[i] >= INITIAL_GIGA_CHAD_TOKEN_ID) {
                totalMucusEarned += (isFrog(tokenIds[i]) ? taxPerGiga : taxPerChad) - stake.previousTaxPer;
            }

            // update stake or unstake
            if (!unstake) {
                stake.previousClaimTimestamp = block.timestamp;
                stake.previousTaxPer = isFrog(tokenIds[i]) ? taxPerGiga : taxPerChad;
                stake.previousSoupIndex = LPStaking.currentSoupIndex();
                farm[tokenIds[i]] = stake;
            } else {
                if (tokenIds[i] >= INITIAL_GIGA_CHAD_TOKEN_ID) {
                    uint256[] storage stakedTokenIds = isFrog(tokenIds[i]) ? gigasStaked : chadsStaked;
                    uint256 lastStakedTokenId = stakedTokenIds[stakedTokenIds.length - 1];
                    Stake storage lastStaked = farm[lastStakedTokenId];

                    stakedTokenIds[stake.gigaOrChadIndex] = lastStakedTokenId; // Shuffle last giga or chad to current position
                    lastStaked.gigaOrChadIndex = stake.gigaOrChadIndex;
                    staked.pop(); // Remove duplicate
                }
                delete farm[tokenIds[i]]; // Delete old mapping
                frogsAndDogs.safeTransferFrom(address(this), _msgSender, tokenIds[i], ""); // transfer the frog or dog back to owner

                emit TokenUnstaked(parent, tokenId);
            }
        }

        if (chadsStaked.length == 0) {
            unclaimedChadTax += totalClaimableChadTax;
        } else {
            taxPerChad += (totalClaimableChadTax + unclaimedChadTax) / chadsStaked.length;
            unclaimedChadTax = 0;
        }
        if (gigasStaked.length == 0) {
            unclaimedGigaTax += totalClaimableGigaTax;
        } else {
            taxPerGiga += (totalClaimableGigaTax + unclaimedgigaTax) / gigasStaked.length;
            unclaimedGigaTax = 0;
        }

        if (totalMucusEarned > 0 && totalMucusMinted < MAX_MUCUS_MINTED) {
            uint256 mucusToMint = totalMucusMinted + totalMucusEarned > MAX_MUCUS_MINTED
                ? MAX_MUCUS_MINTED - totalMucusMinted
                : totalMucusEarned;
            totalMucusMinted += mucusToMint;
            mucus.mint(_msgSender(), mucusToMint);

            emit TokenFarmed(tokenIds[i], mucusToMint);
        }
        if (totalBurnableTax > 0 && totalMucusMinted < MAX_MUCUS_MINTED) {
            uint256 mucusToBurn = totalMucusMinted + totalBurnableTax > MAX_MUCUS_MINTED
                ? MAX_MUCUS_MINTED - totalMucusMinted
                : totalBurnableTax;
            totalMucusMinted += mucusToBurn;
            mucus.mint(DEAD, mucusToBurn);

            emit MucusBurned(mucusToBurn);
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
        uint256 mucusRate = tokenIds[i] >= INITIAL_GIGA_CHAD_TOKEN_ID ? DAILY_MUCUS_RATE * 3 : DAILY_MUCUS_RATE;
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
                        .mul(mucusRate).mul(5).div(100).div(1 days);
                } else {
                    claimableTax += ((previousSoupCycle.timestamp + soupCycleDuration) - stake.previousClaimTimestamp)
                        .mul(mucusRate).mul(20).div(100).div(1 days);
                }
            }

            // cycles passed
            // -1 to account for the previous leftover cycle and if the previous recorded cycle was a frog cycle
            uint256 soupCyclesPassed = currentSoupIndex - stake.previousSoupIndex - 1;
            uint256 totalFrogWinsPassed =
                currentSoupCycle.totalFrogWins - previousSoupCycle.totalFrogWins - previousSoupCycle.soupedUp; // If the previous leftover cycle was a frog cycle, don't count it again
            uint256 totalDogWinsPassed = soupCyclesPassed - totalFrogWinsPassed;
            if (isFrog(tokenId)) {
                claimableTax += totalDogWinsPassed.mul(mucusRate).mul(soupCycleDuration).mul(20).div(100);
                burnableTax += totalFrogWinsPassed.mul(mucusRate).mul(soupCycleDuration).mul(5).div(100);
            } else {
                claimableTax += totalFrogWinsPassed.mul(mucusRate).mul(soupCycleDuration).mul(20).div(100);
                burnableTax += totalDogWinsPassed.mul(mucusRate).mul(soupCycleDuration).mul(5).div(100);
            }
        }

        // current leftover
        // to cover the case when the user claims twice in one cycle
        uint256 previousTimestamp = currentSoupCycle.timestamp > stake.previousClaimTimestamp
            ? currentSoupCycle.timestamp
            : stake.previousClaimTimestamp;
        if (isFrog(tokenId) == currentSoupCycle.soupedUp) {
            burnableTax += (block.timestamp - previousTimestamp).mul(mucusRate).mul(5).div(100).div(1 days);
        } else {
            claimableTax += (block.timestamp - previousTimestamp).mul(mucusRate).mul(20).div(100).div(1 days);
        }

        return (burableTax, claimableTax);
    }

    function rescue(uint256[] calldata tokenIds) external {
        require(rescueEnabled, "Rescue mode not enabled");
        uint256 tokenId;
        Stake memory stake;
        uint256[] staked;
        uint256 lastStakeTokenId;
        Stake memory lastStake;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            stake = farm[tokenId];
            require(stake.owner == _msgSender(), "Cannot unstake tokens that you don't own");
            if (tokenId >= INITIAL_GIGA_CHAD_TOKEN_ID) {
                staked = isFrog(tokenId) ? gigasStaked : chadsStaked;
                lastStakeTokenId = staked[staked.length - 1];
                lastStake = farm[lastStakeTokenId];
                staked[stake.gigaOrChadIndex] = lastStakeTokenId; // Shuffle last Wolf to current position
                farm[lastStakeTokenId].gigaOrChadIndex = stake.gigaOrChadIndex;
                staked.pop(); // Remove duplicate
            }
            frogsAndDogs.safeTransferFrom(address(this), _msgSender(), tokenId, ""); // send back Sheep
            delete farm[tokenId]; // Delete old mapping
        }
    }

    function isFrog(uint256 tokenId) internal pure returns (uint256) {
        return tokenId % 2;
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
