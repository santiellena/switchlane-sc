// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeploySwitchlane} from "../../script/DeploySwitchlane.s.sol";
import {Switchlane} from "../../src/Switchlane.sol";
import {LinkToken} from "../mock/LinkToken.sol";
import {DeploySwitchlane} from "../../script/DeploySwitchlane.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mock/MockV3Aggregator.sol";

contract SwitchlaneTest is Test {
    HelperConfig helperConfig;
    DeploySwitchlane deployer;
    MockV3Aggregator wethPriceFeed;
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

    // USER THAT HOLDS THE ERC20 TOKENS AND WANTS TO SEND THEM
    address public USER = makeAddr("USER");

    // THE ENTRY POINT THAT EXECUTES THE USER OPERATIONS
    address public ENTRY_POINT = makeAddr("ENTRY_POINT");

    uint256 public constant INITIAL_DEPOSIT = 1e18;
    uint256 public constant AMOUNT_TO = 100e6;
    uint256 public constant AMOUNT_FROM = 1e18;
    uint64 public constant POLYGON_DESTINATION_CHAIN = 4051577828743386545;
    uint8 public constant PRICEFEED_DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;

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
        }
        {
            vm.prank(switchlaneOwner);
            wethPriceFeed = new MockV3Aggregator(PRICEFEED_DECIMALS, ETH_USD_PRICE);
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

    modifier whitelistTokenOnChain(uint64 destinationChain, address token) {
        vm.prank(switchlaneOwner);
        switchlane.whitelistTokenOnChain(destinationChain, token);
        _;
    }

    modifier allowlistReceiveToken(address token) {
        vm.prank(switchlaneOwner);
        switchlane.allowlistReceiveToken(token);
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
        whitelistSwapPair(wethTokenAddress, toTokenAddress)
    {
        vm.expectRevert(Switchlane.MustBeMoreThanZero.selector);
        switchlane.calculateLinkFees(wethTokenAddress, toTokenAddress, 0, POLYGON_DESTINATION_CHAIN);
    }

    function testCalculateLinkFeesRevertsIfNotWhitelistedSwapPair() public whitelistChain(POLYGON_DESTINATION_CHAIN) {
        vm.expectRevert(Switchlane.SwapPairNotWhiteListed.selector);
        switchlane.calculateLinkFees(wethTokenAddress, toTokenAddress, 100, POLYGON_DESTINATION_CHAIN);
    }

    function testCalculateLinkFeesRevertsIfDestinationChainIsNotWhitelisted()
        public
        whitelistSwapPair(wethTokenAddress, toTokenAddress)
    {
        vm.expectRevert(Switchlane.DestinationChainNotWhiteListed.selector);
        switchlane.calculateLinkFees(wethTokenAddress, toTokenAddress, 100, POLYGON_DESTINATION_CHAIN);
    }

    function testCalculateProtocolFeesRevertsIfAmountFromTokenIsZero()
        public
        whitelistChain(POLYGON_DESTINATION_CHAIN)
        whitelistSwapPair(wethTokenAddress, toTokenAddress)
    {
        vm.expectRevert(Switchlane.MustBeMoreThanZero.selector);
        switchlane.calculateProtocolFees(wethTokenAddress, toTokenAddress, 0, 100, POLYGON_DESTINATION_CHAIN);
    }

    function testCalculateProtocolFeesRevertsIfAmountToTokenIsZero()
        public
        whitelistChain(POLYGON_DESTINATION_CHAIN)
        whitelistSwapPair(wethTokenAddress, toTokenAddress)
    {
        vm.expectRevert(Switchlane.MustBeMoreThanZero.selector);
        switchlane.calculateProtocolFees(wethTokenAddress, toTokenAddress, 100, 0, POLYGON_DESTINATION_CHAIN);
    }

    function testCalculateProtocolFeesRevertsIfNotWhitelistedSwapPair()
        public
        whitelistChain(POLYGON_DESTINATION_CHAIN)
    {
        vm.expectRevert(Switchlane.SwapPairNotWhiteListed.selector);
        switchlane.calculateProtocolFees(wethTokenAddress, toTokenAddress, 100, 100, POLYGON_DESTINATION_CHAIN);
    }

    function testCalculateProtocolFeesRevertsIfDestinationChainIsNotWhitelisted()
        public
        whitelistSwapPair(wethTokenAddress, toTokenAddress)
    {
        vm.expectRevert(Switchlane.DestinationChainNotWhiteListed.selector);
        switchlane.calculateProtocolFees(wethTokenAddress, toTokenAddress, 100, 100, POLYGON_DESTINATION_CHAIN);
    }

    function testGetTokenUsdValue() public addPriceFeedToToken(wethTokenAddress, address(wethPriceFeed)) {
        uint256 actualPriceWethInUsd = switchlane.getTokenUsdValue(wethTokenAddress, 1e18);
        uint256 expectedPriceWethInUsd = 2000e18;
        assertEq(actualPriceWethInUsd, expectedPriceWethInUsd);
    }

    function testSwitchlaneExactInputRevertsIfAmountIsZero() public {
        vm.prank(switchlaneOwner);
        vm.expectRevert(Switchlane.MustBeMoreThanZero.selector);
        switchlane.switchlaneExactInput(
            address(0), address(0), wethTokenAddress, toTokenAddress, POLYGON_DESTINATION_CHAIN, 0, 100
        );
    }

    function testSwitchlaneExactInputRevertsIfMinimumReceiveAmountIsZero() public {
        vm.prank(switchlaneOwner);
        vm.expectRevert(Switchlane.MustBeMoreThanZero.selector);
        switchlane.switchlaneExactInput(
            address(0), address(0), wethTokenAddress, toTokenAddress, POLYGON_DESTINATION_CHAIN, 100, 0
        );
    }

    function testSwitchlaneExactOutputRevertsIfExpectedOutputAmountIsZero() public {
        vm.prank(switchlaneOwner);
        vm.expectRevert(Switchlane.MustBeMoreThanZero.selector);
        switchlane.switchlaneExactOutput(
            address(0), address(0), wethTokenAddress, toTokenAddress, POLYGON_DESTINATION_CHAIN, 0, 100
        );
    }

    function testSwitchlaneExactOutputRevertsIfAmountIsZero() public {
        vm.prank(switchlaneOwner);
        vm.expectRevert(Switchlane.MustBeMoreThanZero.selector);
        switchlane.switchlaneExactOutput(
            address(0), address(0), wethTokenAddress, toTokenAddress, POLYGON_DESTINATION_CHAIN, 100, 0
        );
    }

    function testWhitelistChain() public {
        vm.prank(switchlaneOwner);
        switchlane.whitelistChain(POLYGON_DESTINATION_CHAIN);

        assert(switchlane.whiteListedChains(POLYGON_DESTINATION_CHAIN));
    }

    function testDenylistChain() public whitelistChain(POLYGON_DESTINATION_CHAIN) {
        vm.prank(switchlaneOwner);
        switchlane.denylistChain(POLYGON_DESTINATION_CHAIN);

        assert(!switchlane.whiteListedChains(POLYGON_DESTINATION_CHAIN));
    }

    function testWhitelistTokenOnChain() public {
        vm.prank(switchlaneOwner);
        switchlane.whitelistTokenOnChain(POLYGON_DESTINATION_CHAIN, wethTokenAddress);

        assert(switchlane.whiteListedTokensOnChains(POLYGON_DESTINATION_CHAIN, wethTokenAddress));
    }

    function testDenylistTokenOnChain() public whitelistTokenOnChain(POLYGON_DESTINATION_CHAIN, wethTokenAddress) {
        vm.prank(switchlaneOwner);
        switchlane.denylistTokenOnChain(POLYGON_DESTINATION_CHAIN, wethTokenAddress);

        assert(!switchlane.whiteListedTokensOnChains(POLYGON_DESTINATION_CHAIN, wethTokenAddress));
    }

    function testAllowlistReceiveToken() public {
        vm.prank(switchlaneOwner);
        switchlane.allowlistReceiveToken(toTokenAddress);

        assert(switchlane.whiteListedReceiveTokens(toTokenAddress));
    }

    function testDenylistReceiveToken() public allowlistReceiveToken(toTokenAddress) {
        vm.prank(switchlaneOwner);
        switchlane.denylistReceiveToken(toTokenAddress);

        assert(!switchlane.whiteListedReceiveTokens(toTokenAddress));
    }

    function testWhitelistSwapPair() public {
        vm.prank(switchlaneOwner);
        switchlane.whitelistSwapPair(wethTokenAddress, toTokenAddress);

        assert(switchlane.whiteListedSwapPair(wethTokenAddress, toTokenAddress));
    }

    function testDenylistSwapPair() public whitelistSwapPair(wethTokenAddress, toTokenAddress) {
        vm.prank(switchlaneOwner);
        switchlane.denylistSwapPair(wethTokenAddress, toTokenAddress);

        assert(!switchlane.whiteListedSwapPair(wethTokenAddress, toTokenAddress));
    }

    function testChangePoolFee() public {
        uint24 actualPreviousPoolFee = switchlane.poolFee();
        uint24 expectedPreviousPoolFee = 3000;

        assertEq(actualPreviousPoolFee, expectedPreviousPoolFee);

        vm.prank(switchlaneOwner);
        uint24 newPoolFee = 1500;
        switchlane.changePoolFee(newPoolFee);

        assertEq(newPoolFee, switchlane.poolFee());
    }

    function testAddPriceFeedUsdAddressToToken() public {
        vm.startPrank(switchlaneOwner);

        switchlane.addPriceFeedUsdAddressToToken(wethTokenAddress, address(wethPriceFeed));
        address actualPriceFeedAddress = switchlane.getTokenPriceFeedAddress(wethTokenAddress);
        vm.stopPrank();

        assertEq(address(wethPriceFeed), actualPriceFeedAddress);
    }

    function testRemovePriceFeedUsdAddressToToken()
        public
        addPriceFeedToToken(wethTokenAddress, address(wethPriceFeed))
    {
        vm.startPrank(switchlaneOwner);

        switchlane.removePriceFeedUsdAddressToToken(wethTokenAddress);
        address actualPriceFeedAddress = switchlane.getTokenPriceFeedAddress(wethTokenAddress);
        vm.stopPrank();

        assertEq(address(0), actualPriceFeedAddress);
    }

    function testGetRouterAddress() public {
        address actualRouterAddress = switchlane.getRouterAddress();
        address expectedRouterAddress = router;

        assertEq(actualRouterAddress, expectedRouterAddress);
    }

    function testGetLinkTokenAddress() public {
        address actualLinkTokenAddress = switchlane.getLinkTokenAddress();
        address expectedLinkTokenAddress = linkAddress;

        assertEq(actualLinkTokenAddress, expectedLinkTokenAddress);
    }

    function testGetSwapRouterAddress() public {
        address actualSwapRouterAddress = switchlane.getSwapRouter();
        address expectedSwapRouterAddress = swapRouter;

        assertEq(actualSwapRouterAddress, expectedSwapRouterAddress);
    }
}
