// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract MockRouter {
    uint256 public immutable FEE;

    constructor(uint256 fee) {
        FEE = fee;
    }

    function getFee(uint64, /*destinationChain*/ Client.EVM2AnyMessage memory /*message*/ )
        external
        view
        returns (uint256)
    {
        return FEE;
    }
}
