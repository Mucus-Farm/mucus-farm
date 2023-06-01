// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IDividendsPairStaking} from "./interfaces/IDividendsPairStaking.sol";

contract Mucus is ERC20 {
    uint16 public teamFee = 2;
    uint16 public stakerFee = 2;
    uint16 public liquidityFee = 2;
    uint16 public totalFee = teamFee + stakerFee + liquidityFee;
    uint16 public denominator = 100;
    bool private swapping;
    bool public swapEnabled = true;
    uint256 private tokenSupply = 9393 * 1e8 * 1e18;
    uint256 public swapTokensAtAmount = 278787 * 1e18;

    mapping(address => bool) private isFeeExempt;
    address teamWallet;
    address _owner;

    IDividendsPairStaking private dividendsPairStaking;
    IUniswapV2Router02 public router;
    address public pair;
    address public mucusFarm;

    constructor(address _uniswapRouter02) ERC20("Mucus", "MUCUS") {
        router = IUniswapV2Router02(_uniswapRouter02);
        pair = IUniswapV2Factory(router.factory()).createPair(address(this), router.WETH());

        isFeeExempt[address(router)] = true;
        isFeeExempt[address(this)] = true;
        isFeeExempt[_owner] = true;

        _owner = msg.sender;
        _mint(msg.sender, tokenSupply);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
    }

    modifier onlyMucusFarm() {
        require(msg.sender == address(mucusFarm));
        _;
    }

    function mint(address to, uint256 amount) external onlyMucusFarm {
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) external onlyMucusFarm {
        _burn(account, amount);
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

        uint256 fees = 0;
        // don't run this if it's currently swapping, if either the sender or the reciever is fee exempt, or if it's not a buy or sell
        if (!swapping && !(isFeeExempt[from] || isFeeExempt[to]) && (pair == from || pair == to)) {
            fees = amount * totalFee / denominator;
            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function swapBack() private {
        uint256 currentBalance = balanceOf(address(this));
        uint256 liquidityFeeHalf = liquidityFee >> 1; // shifts it to the right by one bit, which is the same as dividing by 2
        uint256 tokensForStakers = currentBalance * stakerFee / totalFee;
        uint256 tokensForliquidity = currentBalance * liquidityFeeHalf / totalFee;
        uint256 tokensToSwapForEth = currentBalance - tokensForStakers - tokensForliquidity;

        uint256 initialEthBalance = address(this).balance;
        swapTokensForEth(tokensToSwapForEth);
        uint256 ethBalance = address(this).balance - initialEthBalance;

        uint256 ethForLiquidity = ethBalance * liquidityFeeHalf / (liquidityFeeHalf + teamFee);
        uint256 ethForTeam = ethBalance - ethForLiquidity;

        addLiquidity(tokensForliquidity, ethForLiquidity);

        bool stakersTransferSuccess = super.transfer(address(dividendsPairStaking), tokensForStakers);
        if (stakersTransferSuccess) {
            dividendsPairStaking.deposit(tokensForStakers);
        }

        (bool teamTransferSuccess,) = address(teamWallet).call{value: ethForTeam}("");
        require(teamTransferSuccess, "Failed to send ETH to team wallet");
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
            _owner,
            block.timestamp
        );
    }

    function setMucusFarm(address _mucusFarm) external onlyOwner {
        mucusFarm = _mucusFarm;
        isFeeExempt[_mucusFarm] = true;
    }

    function setDividendsPairStaking(address _dividendsPairStaking) external onlyOwner {
        dividendsPairStaking = IDividendsPairStaking(_dividendsPairStaking);
        isFeeExempt[_dividendsPairStaking] = true;
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}
