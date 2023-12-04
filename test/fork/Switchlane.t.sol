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
    address toTokenAddress;
    address switchlaneOwner;

    address wethPriceFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // USER THAT HOLDS THE ERC20 TOKENS AND WANTS TO SEND THEM
    address public USER = makeAddr("USER");

    // THE ENTRY POINT THAT EXECUTES THE USER OPERATIONS
    address public ENTRY_POINT = makeAddr("ENTRY_POINT");

    uint256 public constant INITIAL_DEPOSIT = 1e18;
    uint64 public constant ARBITRUM_DESTINATION_CHAIN = 4949039107694359620;

    function setUp() public {
        // Brackets are used to avoid the "Stack Too Deep" issue
        // For more information: https://medium.com/aventus/stack-too-deep-error-in-solidity-5b8861891bae
        {
            deployer = new DeploySwitchlane();

            (switchlane, helperConfig) = deployer.run();
        }
        {
            (router, linkAddress, swapRouter, fees, deployerKey, wethTokenAddress, toTokenAddress) =
                helperConfig.activeNetworkConfig();

            switchlaneOwner = switchlane.owner();

            // Give some fromTokens (WETH) for USER
            IWETH(payable(wethTokenAddress)).deposit{value: INITIAL_DEPOSIT}();
            IWETH(payable(wethTokenAddress)).transfer(USER, INITIAL_DEPOSIT);
        }
    }

    // MODIFIERS SECTION

    modifier whitelistSwapPair(address fromToken, address toToken) {
        vm.prank(switchlaneOwner);
        switchlane.whitelistSwapPair(fromToken, toToken);
        _;
    }

    modifier whitelistChain(uint64 destinationChain) {
        vm.prank(switchlaneOwner);
        switchlane.whitelistChain(destinationChain);
        _;
    }

    modifier addPriceFeedToToken(address token, address priceFeed) {
        vm.prank(switchlaneOwner);
        switchlane.addPriceFeedUsdAddressToToken(token, priceFeed);
        _;
    }

    function testBalance() public {
        uint256 balance = IWETH(payable(wethTokenAddress)).balanceOf(USER);

        assertEq(balance, INITIAL_DEPOSIT);
    }

    function testWithdrawTokenRevertsIfNotCalledByOwner() public {
        vm.prank(USER);
        vm.expectRevert("Only callable by owner");
        switchlane.withdrawToken(USER, wethTokenAddress);
    }

    function testWithdrawTokenRevertsIfBalanceOfTokenIsZero() public {
        vm.prank(switchlaneOwner);
        vm.expectRevert(Switchlane.NothingToWithdraw.selector);
        switchlane.withdrawToken(USER, wethTokenAddress);
    }

    function testWithdrawToken() public {
        vm.prank(USER);
        IWETH(payable(wethTokenAddress)).transfer(address(switchlane), INITIAL_DEPOSIT);

        assertEq(IWETH(payable(wethTokenAddress)).balanceOf(USER), 0);

        vm.prank(switchlaneOwner);
        switchlane.withdrawToken(switchlaneOwner, wethTokenAddress);

        assertEq(IWETH(payable(wethTokenAddress)).balanceOf(switchlaneOwner), INITIAL_DEPOSIT);
    }

    function testCalculateLinkFees()
        public
        whitelistSwapPair(wethTokenAddress, toTokenAddress)
        whitelistChain(ARBITRUM_DESTINATION_CHAIN)
    {
        vm.prank(switchlaneOwner);
        uint256 linkFees =
            switchlane.calculateLinkFees(wethTokenAddress, toTokenAddress, 1e18, ARBITRUM_DESTINATION_CHAIN);

        console.log("LINK used on CCIP: ", linkFees);
        assert(linkFees > 0);
    }

    function testCalculateProtocolFees()
        public
        whitelistSwapPair(wethTokenAddress, toTokenAddress)
        whitelistChain(ARBITRUM_DESTINATION_CHAIN)
        addPriceFeedToToken(toTokenAddress, fees.linkPriceFeedAddress) // This is like this because I'm using LINK as toToken
        addPriceFeedToToken(wethTokenAddress, wethPriceFeed)
    {
        uint256 AMOUNT_WETH_SENT = 1e18;
        uint256 EXPECTED_TO_TOKEN_AMOUNT = 100e18;

        vm.prank(USER);
        uint256 feesInUsd = switchlane.calculateProtocolFees(
            wethTokenAddress, toTokenAddress, AMOUNT_WETH_SENT, EXPECTED_TO_TOKEN_AMOUNT, ARBITRUM_DESTINATION_CHAIN
        );

        console.log("PROTOCOL FEES IN USD: ", feesInUsd);
        assert(feesInUsd > 0);
    }
}
