// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeploySwitchlane} from "../../script/DeploySwitchlane.s.sol";
import {Switchlane} from "../../src/Switchlane.sol";
import {LinkToken} from "../mock/LinkToken.sol";
import {DeploySwitchlane} from "../../script/DeploySwitchlane.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

interface IWETH is IERC20 {
    receive() external payable;
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

// WETH ----> USDC
contract SwitchlaneForkTest is Test {
    HelperConfig helperConfig;
    DeploySwitchlane deployer;
    uint256 deployerKey;
    Switchlane switchlane;
    address linkAddress;
    // The Fees struct was made to avoid the "Stack Too Deep" issue
    // Fees { uint256 linkMarginFee, uint24 poolFee, address linkPriceFeedAddress }
    HelperConfig.Fees fees;
    address router;
    address swapRouter;
    address wethTokenAddress;
    address usdcTokenAddress;

    // USER THAT HOLDS THE ERC20 TOKENS AND WANTS TO SEND THEM
    address public USER = makeAddr("USER");

    // THE ENTRY POINT THAT EXECUTES THE USER OPERATIONS
    address public ENTRY_POINT = makeAddr("ENTRY_POINT");

    uint256 constant INITIAL_DEPOSIT = 1e18;

    function setUp() public {
        // Brackets are used to avoid the "Stack Too Deep" issue
        // For more information: https://medium.com/aventus/stack-too-deep-error-in-solidity-5b8861891bae
        {
            deployer = new DeploySwitchlane();

            (switchlane, helperConfig) = deployer.run();
        }
        {
            (router, linkAddress, swapRouter, fees, deployerKey, wethTokenAddress, usdcTokenAddress) =
                helperConfig.activeNetworkConfig();
        }
        {
            // Give some fromTokens (WETH) for USER
            vm.startBroadcast(deployerKey);
            IWETH(payable(wethTokenAddress)).deposit{value: INITIAL_DEPOSIT}();
            IWETH(payable(wethTokenAddress)).transfer(USER, INITIAL_DEPOSIT);
            vm.stopBroadcast();
        }
    }

    function testBalance() public {
        uint256 balance = IWETH(payable(wethTokenAddress)).balanceOf(USER);

        assertEq(balance, INITIAL_DEPOSIT);
    }
}
