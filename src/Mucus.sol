// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";
import {IDividendsPairStaking} from "./interfaces/IDividendsPairStaking.sol";

contract Mucus is ERC20 {
    uint16 public stakerFee = 4;
    uint16 public teamFee = 1;
    uint16 public liquidityFee = 1;
    uint16 public totalFee = teamFee + stakerFee + liquidityFee;
    uint16 public denominator = 100;
    bool private _swapping;
    bool public swapEnabled = true;

    uint256 public constant MAX_SUPPLY = 9393 * 1e8 * 1e18;
    uint256 public constant INITIAL_MINT_SUPPLY = 3131 * 1e8 * 1e18;
    uint256 public constant SWAP_TOKENS_AT_AMOUNT = 278787 * 1e18;

    mapping(address => bool) private isFeeExempt;
    address private teamWallet;
    address private _owner;

    IDividendsPairStaking public dividendsPairStaking;
    IUniswapV2Router02 public router;
    address public pair;
    address public mucusFarm;
    address public frogsAndDogs;

    constructor(address _teamWallet) ERC20("Mucus", "MUCUS") {
        router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        pair = IUniswapV2Factory(router.factory()).createPair(address(this), router.WETH());

        isFeeExempt[address(router)] = true;
        isFeeExempt[address(this)] = true;
        isFeeExempt[msg.sender] = true;

        _owner = msg.sender;
        teamWallet = _teamWallet;

        _mint(msg.sender, INITIAL_MINT_SUPPLY);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
    }

    modifier onlyMucusFarm() {
        require(msg.sender == address(mucusFarm));
        _;
    }

    modifier onlyFrogsAndDogs() {
        require(msg.sender == address(frogsAndDogs));
        _;
    }

    function mint(address to, uint256 amount) external onlyMucusFarm {
        require(totalSupply() + amount < MAX_SUPPLY, "total supply exceeded");
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) external onlyFrogsAndDogs {
        _burn(account, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= SWAP_TOKENS_AT_AMOUNT;

        if (canSwap && !_swapping && from != address(pair)) {
            _swapping = true;
            _swapBack();
            _swapping = false;
        }

        if (!_swapping && block.timestamp >= dividendsPairStaking.nextSoupCycle()) {
            dividendsPairStaking.cycleSoup();
        }

        uint256 fees = 0;
        // don't run this if it's currently _swapping, if either the sender or the reciever is fee exempt, or if it's not a buy or sell
        if (!_swapping && !(isFeeExempt[from] || isFeeExempt[to]) && (pair == from || pair == to)) {
            fees = amount * totalFee / denominator;
            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function _swapBack() private {
        uint256 currentBalance = balanceOf(address(this));
        uint16 liquidityFeeHalf = liquidityFee >> 1;
        uint256 tokensForStakers = currentBalance * stakerFee / totalFee;
        uint256 tokensForliquidity = currentBalance * liquidityFeeHalf / totalFee;
        uint256 tokensToSwapForEth = currentBalance - tokensForStakers - tokensForliquidity;

        uint256 initialEthBalance = address(this).balance;
        _swapTokensForEth(tokensToSwapForEth);
        uint256 ethBalance = address(this).balance - initialEthBalance;

        uint256 ethForLiquidity = ethBalance * liquidityFeeHalf / (liquidityFeeHalf + teamFee);
        uint256 ethForTeam = ethBalance - ethForLiquidity;

        _addLiquidity(tokensForliquidity, ethForLiquidity);

        super._transfer(address(this), address(dividendsPairStaking), tokensForStakers);
        dividendsPairStaking.deposit(tokensForStakers);

        (bool teamTransferSuccess,) = address(teamWallet).call{value: ethForTeam}("");
        require(teamTransferSuccess, "Failed to send ETH to team wallet");
    }

    function _swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), tokenAmount);

        // make the swap
        router.swapExactTokensForETH(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(router), tokenAmount);

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

    function setDividendsPairStaking(address _dividendsPairStaking) external onlyOwner {
        dividendsPairStaking = IDividendsPairStaking(_dividendsPairStaking);
        isFeeExempt[_dividendsPairStaking] = true;
    }

    function setMucusFarm(address _mucusFarm) external onlyOwner {
        mucusFarm = _mucusFarm;
        isFeeExempt[_mucusFarm] = true;
    }

    function setFrogsAndDogs(address _frogsAndDogs) external onlyOwner {
        frogsAndDogs = _frogsAndDogs;
    }

    function setIsFeeExempt(address _feeExempt) external onlyOwner {
        isFeeExempt[_feeExempt] = true;
    }

    function withdraw() external onlyOwner {
        (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
        require(success, "Failed to send ETH");
    }

    receive() external payable {}
}
