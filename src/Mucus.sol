// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";

contract Mucus is ERC20 {
    using SafeMath for uint256;

    uint256 private tokenSupply = 9393 * 1e8 * 1e18;
    uint256 public teamFee = 2;
    uint256 public stakerFee = 2;
    uint256 public liquidityFee = 2;
    uint256 public totalFee = teamFee + stakerFee + liquidityFee;
    uint256 public denominator = 100;

    address _owner;

    // swapping back logic
    uint256 public swapTokensAtAmount = 278787 * 1e18;
    bool private swapping;
    bool public swapEnabled = true;

    // fees and what not
    mapping(address => bool) private isFeeExempt;
    address teamWallet;

    IDividendsPairStaking public dividendsPairStaking;
    ISwampAndYArd public swampAndYard;
    IUniswapV2Router02 public router;
    address public pair;

    event StakeAdded(address indexed staker, uint256 amount);
    event StakeRemoved(address indexed staker, uint256 amount);
    event DividendsPerShareUpdated(uint256 dividendsPerShare);

    constructor(address _LPStaking) ERC20("Mucus", "MUCUS") {
        router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        pair = IUniswapV2Factory(router.factory()).createPair(address(this), router.WETH());
        dividendsPairStaking = new DividendsPairStaking(msg.sender, pair);

        _owner = msg.sender;
        _mint(msg.sender, tokenSupply);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Time based rewards?
    // When a new staker comes on and stakes their LP tokens, the last recorded divdendsPerLP is set in their struct
    // When they go to claim, the difference between the current dividendsPerLP and the current dividendsPerLP is rewarded and
    // the dividendsPerLP is updated to the current dividendsPerLP
    // This allows for early investors to be able to be rewarded more since its on a time basis. So every x amount of trades that happen
    // It will get recorded for them in the dividendsPerLP variable
    // could technically be as simple as dividendsPerLP = dividendsPerLP + (currentContractBalance / totalLPs)
    function _transfer(address from, address to, uint256 amount) internal override {
        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        // maybe there doesn't need to be a swap back function?
        // Does more liquidity need to be added in?
        if (canSwap && !swapping && from != address(pair) && !isFeeExempt[from]) {
            swapping = true;
            swapBack();
            swapping = false;
        }

        if (block.timestamp >= dividendsPairStaking.nextSoupCycle()) {
            dividendsPairStaking.cycleSoup();
        }

        // don't run this if it's currently swapping, if either the sender or the reciever is fee exempt, or if it's not a buy or sell
        if (!swapping && !(isFeeExempt[from] || isFeeExempt[to]) && (pair == from || pair == to)) {
            fees = amount.mul(totalFee).div(denominator);
            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function swapBack() private {
        uint256 currentBalance = balanceOf(address(this));
        uint256 tokensForStakers = currentBalance.mul(stakerFee).div(totalFee);
        uint256 tokensForliquidity = currentBalance.mul(liquidityFee / 2).div(totalFee);
        uint256 tokensToSwapForEth = currentBalance.sub(tokensForStakers).sub(tokensForliquidity);

        uint256 initialEthBalance = address(this).balance;
        swapTokensForEth(tokensToSwapForEth);
        uint256 ethBalance = address(this).balance - initialEthBalance;

        uint256 ethForLiquidity = ethBalance.mul(liquidityFee / 2).div((liquidityFee / 2) + teamFee);
        uint256 ethForTeam = ethBalance.sub(ethForLiquidity);

        addLiquidity(tokensForliquidity, ethForLiquidity);

        bool stakersTransferSuccess = super.transfer(address(diviends), tokensForStakers);
        if (stakersTransferSuccess) {
            dividendsPairStaking.deposit(tokensForStakers);
        }

        (bool teamTransferSuccess,) = address(teamWallet).call{value: ethForTeam}("");
        require(teamTransferSuccess, "Failed to send ETH to team wallet");

        emit DividendsPerShareUpdated(dividendsPerShare);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), tokenAmount);

        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(router), tokenAmount);

        // add the liquidity
        // add the liquidity
        router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    function setSwampAndYard(address _swampAndYard) external onlyOwner {
        swampAndYard = ISwampAndYard(_swampAndYard);
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}
