// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Switchlane} from "../src/Switchlane.sol";

contract DeploySwitchlane is Script {
    Switchlane switchlane;

    function run() public returns (Switchlane, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (
            address routerAddress,
            address linkAddress,
            address swapRouterAddress,
            HelperConfig.Fees memory fees,
            uint256 deployerKey,
            ,
        ) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);

        switchlane =
        new Switchlane(routerAddress, linkAddress, fees.poolFee, swapRouterAddress, fees.linkMarginFee, fees.linkPriceFeedAddress);

        vm.stopBroadcast();

        return (switchlane, helperConfig);
    }
}
