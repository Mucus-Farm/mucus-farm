// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {IDividendsPairStaking} from "./interfaces/IDividendsPairStaking.sol";

contract DividendsPairStaking is IDividendsPairStaking {
    using SafeMath for uint256;

    uint256 public totalDogFactionAmount;
    uint256 public totalFrogFactionAmount;
    uint256 public dividendsPerShare;
    mapping(address => Staker) public stakers;
    uint256 public totalStakedAmount;

    mapping(uint256 => SoupCycle) public soupCycles;
    uint256 private dividendsPerShareAccuracyFactor = 10 ** 36;
    // TODO: should there be a flag to determine if its time to start soupuing?
    uint256 public currentSoupIndex;
    uint256 public soupCycleDuration = 3 days;
    IERC20 public LPToken;

    address private _token;
    address private _owner;

    constructor(address owner, address pair) {
        LPToken = IERC20(pair);
        _token = msg.sender;
        _owner = owner;

        soupCycles[currentSoupIndex] = SoupCycle({timestamp: block.timestamp, soupedUp: Faction.FROG, totalFrogWins: 0});
    }

    modifier onlyTokenOrOwner() {
        require(msg.sender == _token || msg.sender == _owner);
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
    }

    function nextSoupCycle() external view returns (uint256) {
        return soupCycles[currentSoupIndex].timestamp + soupCycleDuration;
    }

    function addStake(uint256 amount, Faction faction) external {
        require(amount > 0, "Cannot stake 0 tokens");

        // This is equivalent to taring it to 0
        // This makes it so that the math to calculate the dps stays consistent
        if (stakers[msg.sender].totalAmount > 0) {
            distributeDividend(msg.sender);
        }

        if (stakers[msg.sender].totalAmount == 0) {
            stakers[msg.sender] = Staker(amount, dividendsPerShare, 0, 0, block.timestamp + 1 weeks);
        } else {
            stakers[msg.sender].totalAmount += amount;
        }

        if (faction == Faction.DOG) {
            stakers[msg.sender].dogFactionAmount += amount;
            totalDogFactionAmount += amount;
        } else {
            stakers[msg.sender].frogFactionAmount += amount;
            totalFrogFactionAmount += amount;
        }
        totalStakedAmount += amount;

        LPToken.transferFrom(msg.sender, address(this), amount);

        emit StakeAdded(msg.sender, amount);
    }

    function removeStake(uint256 amount, Faction faction) external {
        require(amount >= stakers[msg.sender].totalAmount, "Cannot unstake more than you have staked");
        require(
            faction != Faction.DOG || stakers[msg.sender].dogFactionAmount >= amount,
            "Cannot unstake more than you have staked for the dog faction"
        );
        require(
            faction != Faction.FROG || stakers[msg.sender].frogFactionAmount >= amount,
            "Cannot unstake more than you have staked for the frog faction"
        );
        require(block.timestamp > stakers[msg.sender].lockingEndDate, "Cannot unstake until locking period is over");

        // This is equivalent to taring it to 0
        // This makes it so that the math to calculate the dps stays consistent
        if (stakers[msg.sender].totalAmount > 0) {
            distributeDividend(msg.sender);
        }

        if (stakers[msg.sender].totalAmount == amount) {
            delete stakers[msg.sender];
        } else {
            stakers[msg.sender].totalAmount -= amount;
        }

        if (faction == Faction.DOG) {
            totalDogFactionAmount -= amount;
        } else {
            totalFrogFactionAmount -= amount;
        }
        totalStakedAmount -= amount;

        LPToken.transferFrom(address(this), msg.sender, amount);

        emit StakeRemoved(msg.sender, amount);
    }

    function removeEntireStake() external {
        require(stakers[msg.sender].totalAmount > 0, "Cannot unstake if you haven't staked");
        require(block.timestamp > stakers[msg.sender].lockingEndDate, "Cannot unstake until locking period is over");

        // This is equivalent to taring it to 0
        // This makes it so that the math to calculate the dps stays consistent
        distributeDividend(msg.sender);

        uint256 amount = stakers[msg.sender].totalAmount;
        delete stakers[msg.sender];
        totalStakedAmount -= amount;

        LPToken.transferFrom(address(this), msg.sender, amount);

        emit StakeRemoved(msg.sender, amount);
    }

    function claim() external {
        distributeDividend(msg.sender);
    }

    function distributeDividend(address staker) internal {
        require(stakers[staker].totalAmount > 0, "Cannot distribute to someone who hasn't staked");
        uint256 amount = stakers[staker].totalAmount;
        uint256 previousDividendsPerShare = stakers[staker].previousDividendsPerShare;

        uint256 reward = (dividendsPerShare - previousDividendsPerShare) * amount;

        stakers[staker].previousDividendsPerShare = dividendsPerShare;

        // TODO: think about whether there is a case where reward can be 0 here
        // I'm thinking not since the dividendsPerShare will always be greater than the previousDividendsPerShare, since dividendsPerShare only goes up
        // this results in dividendsPerShare - previousDividendsPerShare > 0
        // this means that the only time this can be 0 is when amount is 0
        // so check to see if amount is 0 before even bothering to try this
        IERC20(_token).transfer(staker, reward);
    }

    function deposit(uint256 amount) external onlyTokenOrOwner {
        if (amount > 0) {
            dividendsPerShare =
                dividendsPerShare.add(dividendsPerShareAccuracyFactor.mul(amount).div(totalStakedAmount));
        }

        emit DividendsPerShareUpdated(dividendsPerShare);
    }

    function cycleSoup() external onlyTokenOrOwner {
        require(
            block.timestamp > soupCycles[currentSoupIndex].timestamp + 3 days,
            "Cannot update soup cycle until the current cycle is over"
        );
        currentSoupIndex++;
        uint256 totalFrogWins = soupCycles[currentSoupIndex].totalFrogWins;
        Faction soupedUp = totalFrogFactionAmount > totalDogFactionAmount ? Faction.FROG : Faction.DOG;
        if (soupedUp == Faction.FROG) totalFrogWins++;
        soupCycles[currentSoupIndex] =
            SoupCycle({timestamp: block.timestamp, soupedUp: soupedUp, totalFrogWins: totalFrogWins});
    }

    function getSoup(uint256 previousSoupIndex)
        external
        view
        returns (uint256, uint256, SoupCycle memory, SoupCycle memory)
    {
        return (currentSoupIndex, soupCycleDuration, soupCycles[previousSoupIndex], soupCycles[currentSoupIndex]);
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}
