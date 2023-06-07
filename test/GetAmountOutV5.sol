pragma solidity >=0.5.0;

import {console} from "forge-std/console.sol";
import {SafeMath} from "./lib/SafeMathV5.sol";

contract GetAmountOutV5 {
    using SafeMath for uint256;

    uint256 amountIn = 500000000000000000000;
    uint256 reserveIn = 100000000000000000000000000000;
    uint256 reserveOut = 100000000998500002492499999999;

    function testGetAmountOut() public {
        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        uint256 amountOut = numerator / denominator;

        console.log("amountOut: ", amountOut);
    }
}
