// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeploySwitchlane} from "../../script/DeploySwitchlane.s.sol";
import {Switchlane} from "../../src/Switchlane.sol";
import {LinkToken} from "../mock/LinkToken.sol";
import {DeploySwitchlane} from "../../script/DeploySwitchlane.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract SwitchlaneTest is Test {
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
    address switchlaneOwner;

    // USER THAT HOLDS THE ERC20 TOKENS AND WANTS TO SEND THEM
    address public USER = makeAddr("USER");

    // THE ENTRY POINT THAT EXECUTES THE USER OPERATIONS
    address public ENTRY_POINT = makeAddr("ENTRY_POINT");

    uint256 public constant INITIAL_DEPOSIT = 1e18;
    uint256 public constant AMOUNT_TO = 100e6;
    uint256 public constant AMOUNT_FROM = 1e18;
    uint64 public constant POLYGON_DESTINATION_CHAIN = 4051577828743386545;

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

            switchlaneOwner = switchlane.owner();
        }
    }

    // MODIFIERS SECTION

    modifier whitelistSwapPair(address fromToken, address toToken) {
        vm.prank(switchlaneOwner);
        switchlane.whiteListedSwapPair(fromToken, toToken);
        _;
    }

    modifier whitelistChain(uint64 destinationChain) {
        vm.prank(switchlaneOwner);
        switchlane.whitelistChain(destinationChain);
        _;
    }

    // TESTS SECTION

    function testWithdrawTokenRevertsIfNothingToWithdraw() public {
        vm.prank(switchlaneOwner);
        vm.expectRevert(Switchlane.NothingToWithdraw.selector);
        switchlane.withdrawToken(USER, wethTokenAddress);
    }

    function testWithdrawTokenRevertsIfNotOwner() public {
        vm.prank(USER);
        vm.expectRevert("Only callable by owner");
        switchlane.withdrawToken(USER, wethTokenAddress);
    }

    function testCalculateLinkFeesRevertsIfAmountIsZero()
        public
        whitelistChain(POLYGON_DESTINATION_CHAIN)
        whitelistSwapPair(wethTokenAddress, usdcTokenAddress)
    {
        vm.expectRevert(Switchlane.MustBeMoreThanZero.selector);
        switchlane.calculateLinkFees(wethTokenAddress, usdcTokenAddress, 0, POLYGON_DESTINATION_CHAIN);
    }
}
