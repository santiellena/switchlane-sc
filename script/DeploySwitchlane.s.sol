// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Switchlane} from "../src/Switchlane.sol";
import {SwitchlaneExposed} from "../test/SwitchlaneExposed.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract DeploySwitchlane is Script {
    Switchlane switchlane;
    SwitchlaneExposed switchlaneExposed;

    function run() public returns (Switchlane, HelperConfig, SwitchlaneExposed) {
        HelperConfig helperConfig = new HelperConfig();

        (
            address routerAddress,
            address linkAddress,
            address swapRouterAddress,
            HelperConfig.Fees memory fees,
            uint256 deployerKey,
            ,
            ,
            bool test
        ) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);

        switchlane =
        new Switchlane(routerAddress, linkAddress, fees.poolFee, swapRouterAddress, fees.linkMarginFee, fees.linkPriceFeedAddress);

        if (test) {
            switchlaneExposed =
            new SwitchlaneExposed(routerAddress, linkAddress, fees.poolFee, swapRouterAddress, fees.linkMarginFee, fees.linkPriceFeedAddress);
        }

        vm.stopBroadcast();

        return (switchlane, helperConfig, switchlaneExposed);
    }
}
