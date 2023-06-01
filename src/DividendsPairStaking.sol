// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IDividendsPairStaking} from "./interfaces/IDividendsPairStaking.sol";

contract DividendsPairStaking is IDividendsPairStaking {
    uint256 public totalDogFactionAmount;
    uint256 public totalFrogFactionAmount;
    uint256 public dividendsPerFrog;
    uint256 public dividendsPerDog;
    mapping(address => Staker) public stakers;
    uint256 public totalStakedAmount;

    mapping(uint256 => SoupCycle) public soupCycles;
    // TODO: should there be a flag to determine if its time to start soupuing?
    uint256 public currentSoupIndex;
    uint256 public soupCycleDuration = 3 days;

    IUniswapV2Router02 public router;
    IERC20 public pair;
    address private _mucus;
    address private _owner;

    constructor(address mucus, address _uniswapRouter02) {
        router = IUniswapV2Router02(_uniswapRouter02);
        address _pair = IUniswapV2Factory(router.factory()).getPair(mucus, router.WETH());
        pair = IERC20(_pair);
        _mucus = mucus;
        _owner = msg.sender;

        soupCycles[currentSoupIndex] = SoupCycle({timestamp: block.timestamp, soupedUp: Faction.FROG, totalFrogWins: 0});
    }

    modifier onlyTokenOrOwner() {
        require(msg.sender == _mucus || msg.sender == _owner);
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
    }

    function addStake(Faction faction) external payable {
        require(msg.value > 0, "ETH must be sent to stake");
        Staker memory staker = stakers[msg.sender];

        // This is equivalent to taring it to 0
        // This makes it so that the math to calculate the dps stays consistent
        if (staker.totalAmount > 0) {
            distributeDividend();
        }

        uint256 balanceBefore = pair.balanceOf(address(this));
        addLiquidity();
        uint256 balanceAfter = pair.balanceOf(address(this));
        uint256 amount = balanceAfter - balanceBefore;

        // add staker if never staked before
        if (staker.totalAmount == 0) {
            staker.previousDividendsPerFrog = dividendsPerFrog;
            staker.previousDividendsPerDog = dividendsPerDog;
            staker.lockingEndDate = block.timestamp + 1 weeks;
        }
        staker.totalAmount += amount;

        if (faction == Faction.DOG) {
            staker.dogFactionAmount += amount;
            totalDogFactionAmount += amount;
        } else {
            staker.frogFactionAmount += amount;
            totalFrogFactionAmount += amount;
        }
        totalStakedAmount += amount;

        stakers[msg.sender] = staker;

        emit StakeAdded(msg.sender, amount, faction);
    }

    function addLiquidity() private {
        uint256 ethAmount = msg.value >> 1;
        uint256 tokenAmount = swapEthForTokens(ethAmount);

        // approve token transfer to cover all possible scenarios
        IERC20(_mucus).approve(address(router), tokenAmount);

        // add the liquidity
        // add the liquidity
        router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    function swapEthForTokens(uint256 ethAmount) private returns (uint256) {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(_mucus);

        uint256[] memory amounts =
            router.swapExactETHForTokens{value: ethAmount}(0, path, address(this), block.timestamp);

        return amounts[1];
    }

    function removeStake(uint256 amount, Faction faction) external {
        Staker memory staker = stakers[msg.sender];
        require(amount >= staker.totalAmount, "Cannot unstake more than you have staked");
        require(
            faction != Faction.DOG || staker.dogFactionAmount >= amount,
            "Cannot unstake more than you have staked for the dog faction"
        );
        require(
            faction != Faction.FROG || staker.frogFactionAmount >= amount,
            "Cannot unstake more than you have staked for the frog faction"
        );
        require(block.timestamp > staker.lockingEndDate, "Cannot unstake until locking period is over");

        // This is equivalent to taring it to 0
        // This makes it so that the math to calculate the dps stays consistent
        if (staker.totalAmount > 0) {
            distributeDividend();
        }

        if (faction == Faction.DOG) {
            staker.dogFactionAmount -= amount;
            totalDogFactionAmount -= amount;
        } else {
            staker.frogFactionAmount -= amount;
            totalFrogFactionAmount -= amount;
        }

        if (staker.totalAmount == amount) {
            delete stakers[msg.sender];
        } else {
            staker.totalAmount -= amount;
            stakers[msg.sender] = staker;
        }

        totalStakedAmount -= amount;

        pair.transferFrom(address(this), msg.sender, amount);
        (uint256 tokenAmount, uint256 ethAmount) = router.removeLiquidityETH(
            _mucus,
            amount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );

        IERC20(_mucus).transfer(msg.sender, tokenAmount);
        payable(msg.sender).transfer(ethAmount);

        emit StakeRemoved(msg.sender, amount, faction);
    }

    function vote(uint256 amount, Faction faction) external {
        require(amount > 0, "Amount must be greater than 0");
        Staker memory staker = stakers[msg.sender];

        // reset to make it consistent
        if (staker.totalAmount > 0) {
            distributeDividend();
        }

        if (faction == Faction.FROG) {
            require(staker.dogFactionAmount >= amount, "Cannot swap more Dog votes than you have staked");

            staker.dogFactionAmount -= amount;
            staker.frogFactionAmount += amount;
            totalDogFactionAmount -= amount;
            totalFrogFactionAmount += amount;
        } else {
            require(staker.frogFactionAmount >= amount, "Cannot swap more Frog votes than you have staked");

            staker.frogFactionAmount -= amount;
            staker.dogFactionAmount += amount;
            totalFrogFactionAmount -= amount;
            totalDogFactionAmount += amount;
        }

        stakers[msg.sender] = staker;

        emit VoteSwapped(msg.sender, amount, faction);
    }

    function claim() external {
        distributeDividend();
    }

    function distributeDividend() internal {
        Staker memory staker = stakers[msg.sender];

        require(staker.totalAmount > 0, "Cannot distribute to someone who hasn't staked");
        uint256 frogRewards = (dividendsPerFrog - staker.previousDividendsPerFrog) * staker.frogFactionAmount;
        uint256 dogRewards = (dividendsPerDog - staker.previousDividendsPerDog) * staker.dogFactionAmount;

        staker.previousDividendsPerFrog = dividendsPerFrog;
        staker.previousDividendsPerDog = dividendsPerDog;

        stakers[msg.sender] = staker;

        if (frogRewards + dogRewards > 0) {
            IERC20(_mucus).transfer(msg.sender, frogRewards + dogRewards);
        }

        emit DividendsEarned(msg.sender, frogRewards + dogRewards);
    }

    function deposit(uint256 amount) external onlyTokenOrOwner {
        if (amount > 0) {
            uint256 frogAmount = amount * totalDogFactionAmount / totalStakedAmount;
            uint256 dogAmount = amount - frogAmount;
            dividendsPerFrog += frogAmount / totalFrogFactionAmount;
            dividendsPerDog += dogAmount / totalDogFactionAmount;
        }

        emit DividendsPerShareUpdated(dividendsPerFrog, dividendsPerDog);
    }

    function cycleSoup() external onlyTokenOrOwner {
        require(
            block.timestamp > soupCycles[currentSoupIndex].timestamp + 12 hours,
            "Cannot update soup cycle until the current cycle is over"
        );
        currentSoupIndex++;
        uint256 totalFrogWins = soupCycles[currentSoupIndex].totalFrogWins;
        Faction soupedUp = totalFrogFactionAmount > totalDogFactionAmount ? Faction.FROG : Faction.DOG;
        if (soupedUp == Faction.FROG) totalFrogWins++;
        soupCycles[currentSoupIndex] =
            SoupCycle({timestamp: block.timestamp, soupedUp: soupedUp, totalFrogWins: totalFrogWins});

        emit SoupCycled(soupedUp);
    }

    function getSoup(uint256 previousSoupIndex)
        external
        view
        returns (uint256, uint256, SoupCycle memory, SoupCycle memory)
    {
        return (currentSoupIndex, soupCycleDuration, soupCycles[previousSoupIndex], soupCycles[currentSoupIndex]);
    }

    function nextSoupCycle() external view returns (uint256) {
        return soupCycles[currentSoupIndex].timestamp + soupCycleDuration;
    }

    function getSoupedUp() external view returns (Faction) {
        return soupCycles[currentSoupIndex].soupedUp;
    }

    function setSoupCycleDuration(uint256 _soupCycleDuration) external onlyOwner {
        soupCycleDuration = _soupCycleDuration;

        emit SoupCycleDurationUpdated(_soupCycleDuration);
    }

    function withdrawMucus() external onlyOwner {
        IERC20 mucus = IERC20(_mucus);
        mucus.transfer(msg.sender, mucus.balanceOf(address(this)));
    }

    function withdrawEth() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}
