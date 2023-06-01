// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Mucus} from "../src/Mucus.sol";
import {DividendsPairStaking} from "../src/DividendsPairStaking.sol";

contract MucusTest is Test {
    Mucus mucus;
    DividendsPairStaking dps;

    function setUp() public {
        address _uniswapRouter02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        mucus = new Mucus(_uniswapRouter02);
        dps = new DividendsPairStaking(address(mucus), _uniswapRouter02);
        mucus.setDividendsPairStaking(address(dividendsPairStaking));
    }

    function testBuyMucus() public {
        uint256 bal = 100 * 1e18;
        hoax(address(1), bal);
        dps.addLiquidity{value: bal}();
    }
}
