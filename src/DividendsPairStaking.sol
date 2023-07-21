// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";
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
    uint256 public currentSoupIndex;
    uint256 public soupCycleDuration = 3 days;

    IUniswapV2Router02 public router;
    IERC20 public pair;
    address private _mucus;
    address private _owner;

    constructor(address mucus) {
        router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        address _pair = IUniswapV2Factory(router.factory()).getPair(mucus, router.WETH());
        pair = IERC20(_pair);
        _mucus = mucus;
        _owner = msg.sender;

        soupCycles[currentSoupIndex] = SoupCycle({timestamp: block.timestamp, soupedUp: Faction.FROG, totalFrogWins: 1});
    }

    modifier onlyTokenOrOwner() {
        require(msg.sender == _mucus || msg.sender == _owner);
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
    }

    function addStake(Faction faction, uint256 tokenAmountOutMin) external payable {
        require(msg.value > 0, "ETH must be sent to stake");
        Staker memory staker = stakers[msg.sender];

        // This is equivalent to taring it to 0
        // This makes it so that the math to calculate the dps stays consistent
        if (staker.totalAmount > 0) {
            _distributeDividend(staker);
        }

        uint256 amount = _addLiquidity(tokenAmountOutMin);

        // add staker if never staked before
        if (staker.totalAmount == 0) {
            staker.previousDividendsPerFrog = dividendsPerFrog;
            staker.previousDividendsPerDog = dividendsPerDog;
        }

        // TODO: undo this
        // staker.lockingEndDate = block.timestamp + 2 weeks;
        staker.lockingEndDate = block.timestamp;
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

    function _addLiquidity(uint256 tokenAmountOutMin) private returns (uint256) {
        uint256 ethAmount = msg.value >> 1;
        uint256 tokenAmount = _swapEthForTokens(ethAmount, tokenAmountOutMin);

        // approve token transfer to cover all possible scenarios
        IERC20(_mucus).approve(address(router), tokenAmount);

        // add the liquidity
        (,, uint256 liquidity) = router.addLiquidityETH{value: ethAmount}(
            _mucus,
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );

        return liquidity;
    }

    function _swapEthForTokens(uint256 ethAmount, uint256 tokenAmountOutMin) private returns (uint256) {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(_mucus);

        uint256[] memory amounts =
            router.swapExactETHForTokens{value: ethAmount}(tokenAmountOutMin, path, address(this), block.timestamp);

        return amounts[1];
    }

    function removeStake(uint256 amount, Faction faction) external {
        Staker memory staker = stakers[msg.sender];
        require(amount > 0, "Amount must be greater than 0");
        require(staker.totalAmount >= amount, "Cannot unstake more than you have staked");
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
        _distributeDividend(staker);

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

        pair.approve(address(router), amount);
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
        Staker memory staker = stakers[msg.sender];
        require(amount > 0, "Amount must be greater than 0");
        require(staker.totalAmount > 0, "Cannot vote if you haven't staked");

        // reset to make it consistent
        _distributeDividend(staker);

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
        Staker memory staker = stakers[msg.sender];
        require(staker.totalAmount > 0, "Cannot claim if you haven't staked");
        _distributeDividend(staker);
    }

    function _distributeDividend(Staker memory staker) internal {
        // Staker memory staker = stakers[msg.sender];
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
        if (amount > 0 && totalFrogFactionAmount > 0 && totalDogFactionAmount > 0) {
            uint256 frogAmount = amount * totalDogFactionAmount / totalStakedAmount;
            uint256 dogAmount = amount - frogAmount;
            dividendsPerFrog += frogAmount / totalFrogFactionAmount;
            dividendsPerDog += dogAmount / totalDogFactionAmount;
        }

        emit DividendsPerShareUpdated(dividendsPerFrog, dividendsPerDog);
    }

    function cycleSoup() external onlyTokenOrOwner {
        require(
            block.timestamp >= soupCycles[currentSoupIndex].timestamp + soupCycleDuration,
            "Cannot update soup cycle until the current cycle is over"
        );
        uint256 totalFrogWins = soupCycles[currentSoupIndex].totalFrogWins;
        Faction soupedUp = totalFrogFactionAmount > totalDogFactionAmount ? Faction.FROG : Faction.DOG;
        if (soupedUp == Faction.FROG) totalFrogWins++;

        currentSoupIndex++;
        soupCycles[currentSoupIndex] =
            SoupCycle({timestamp: block.timestamp, soupedUp: soupedUp, totalFrogWins: totalFrogWins});

        emit SoupCycled(currentSoupIndex, soupedUp);
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
        (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
        require(success, "Failed to send ETH");
    }

    receive() external payable {}
}
