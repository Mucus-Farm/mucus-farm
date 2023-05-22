// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";

contract Mucus is ERC20, Ownable {
    using SafeMath for uint256;

    uint256 private tokenSupply = 9393 * 1e8 * 1e18;
    uint256 public teamFee = 39; // 3.9%
    uint256 public stakerFee = 29; // 2.9%
    uint256 public totalFee = teamFee + stakerFee;
    uint256 public denominator = 1000;

    // maybe
    uint256 public swapTokensAtAmount = totalSupply * 10 / 2000;
    bool private swapping;
    bool public swapEnabled = true;

    mapping(address => bool) private isFeeExempt;
    uint256 public tokensForTeam;
    uint256 public tokensForStakers;

    IDEXRouter public pair;

    constructor() ERC20("Mucus", "MUCUS") {
        pair = IDEXRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _mint(msg.sender, tokenSupply);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        // if (canSwap && swapEnabled && !swapping && to != address(router) && !isFeeExempt[from] && !isFeeExempt[to]) {
        //     swapping = true;

        //     swapBack();

        //     swapping = false;
        // }

        uint256 fees = 0;
        if (!(isFeeExempt[from] || isFeeExempt[to]) && (pair == from || pair == to)) {
            fees = amount.mul(totalFeeNumerator).div(denominator);
            tokensForTeam += fees * teamFee / totalFee;
            tokensForStakers += fees * stakerFee / totalFee;

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, transferAmount);

        // Implement distributor
    }

    function withdraw() external owner {
        payable(msg.sender).transfer(address(this).balance);
    }
}
