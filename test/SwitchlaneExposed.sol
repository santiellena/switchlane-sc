// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Switchlane} from "../src/Switchlane.sol";

// THIS CONTRACT IS TO EXPOSE INTERNAL FUNCTIONS SO THEY CAN BE TESTED
contract SwitchlaneExposed is Switchlane {
    constructor(
        address _router,
        address _linkToken,
        uint24 _poolFee,
        address _swapRouter,
        uint256 _linkMarginFee,
        address _linkPriceFeedAddress
    ) Switchlane(_router, _linkToken, _poolFee, _swapRouter, _linkMarginFee, _linkPriceFeedAddress) {}

    function calculateSwapFee(uint256 amount) external view returns (uint256) {
        return _calculateSwapFee(amount);
    }

    function receiveTokens(address sender, address token, uint256 amount) external {
        _receiveTokens(sender, token, amount);
    }

    function swapExactInputSingle(address fromToken, address toToken, uint256 amountIn, uint256 amountOutMinimum)
        external
        returns (uint256)
    {
        return _swapExactInputSingle(fromToken, toToken, amountIn, amountOutMinimum);
    }

    function swapExactOutputSingle(address fromToken, address toToken, uint256 amountOut, uint256 amountInMaximum)
        external
        returns (uint256)
    {
        return _swapExactInputSingle(fromToken, toToken, amountOut, amountInMaximum);
    }

    function transferTokens(uint64 _destinationChainSelector, address _receiver, address _token, uint256 _amount)
        external
        returns (bytes32 messageId)
    {
        return _transferTokens(_destinationChainSelector, _receiver, _token, _amount);
    }
}
