// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeploySwitchlane} from "../../script/DeploySwitchlane.s.sol";
import {Switchlane} from "../../src/Switchlane.sol";
import {LinkToken} from "../mock/LinkToken.sol";
import {DeploySwitchlane} from "../../script/DeploySwitchlane.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {SwitchlaneExposed} from "../SwitchlaneExposed.sol";

interface IWETH is IERC20 {
    receive() external payable;
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface ISLN is IERC20 {
    function mint(uint256 amount) external;
}

// WETH ----> USDC

contract SwitchlaneForkTest is Test {
    HelperConfig helperConfig;
    DeploySwitchlane deployer;
    uint256 deployerKey;
    Switchlane switchlane;
    SwitchlaneExposed switchlaneExposed;
    address linkAddress;
    // The Fees struct was made to avoid the "Stack Too Deep" issue
    // Fees { uint256 linkMarginFee, uint24 poolFee, address linkPriceFeedAddress }
    HelperConfig.Fees fees;
    address router;
    address swapRouter;
    address fromTokenAddress;
    address toTokenAddress;
    address switchlaneOwner;

    address wethPriceFeedMainnet = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address wethPriceFeedSepolia = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address maticPriceFeedMumbai = 0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada;

    //  The following price feed is not actually for SLN, it is the LINK/USD price feed
    // As there aren't a price feed for SLN, I'll make a liquidity pool with a 1:1 ratio between
    // these tokens.
    address slnPriceFeedMumbai = 0x1C2252aeeD50e0c9B64bDfF2735Ee3C932F5C408;

    //  Same thing than the previous price feed. As CCIP-BnM doesn't have a price feed I'll make it
    // equal to 1 LINK.
    address ccipBnMPriceFeedMumbai = 0x1C2252aeeD50e0c9B64bDfF2735Ee3C932F5C408;

    // USER THAT HOLDS THE ERC20 TOKENS AND WANTS TO SEND THEM
    address public USER = makeAddr("USER");

    // THE ENTRY POINT THAT EXECUTES THE USER OPERATIONS
    address public ENTRY_POINT = makeAddr("ENTRY_POINT");

    uint256 public constant INITIAL_DEPOSIT = 1e18;
    uint64 public constant ARBITRUM_DESTINATION_CHAIN = 4949039107694359620;
    uint64 public constant BASE_DESTINATION_CHAIN = 15971525489660198786;
    uint64 public constant MUMBAI_DESTINATION_CHAIN = 12532609583862916517;
    uint64 public constant SEPOLIA_DESTINATION_CHAIN = 16015286601757825753;

    uint256 public constant MUMBAI_CHAINID = 80001;

    function setUp() public {
        // Brackets are used to avoid the "Stack Too Deep" issue
        // For more information: https://medium.com/aventus/stack-too-deep-error-in-solidity-5b8861891bae
        {
            deployer = new DeploySwitchlane();

            (switchlane, helperConfig, switchlaneExposed) = deployer.run();
        }
        {
            (router, linkAddress, swapRouter, fees, deployerKey, fromTokenAddress, toTokenAddress,) =
                helperConfig.activeNetworkConfig();

            switchlaneOwner = switchlaneExposed.owner();

            if (block.chainid == MUMBAI_CHAINID) {
                ISLN(fromTokenAddress).mint(INITIAL_DEPOSIT);
                ISLN(fromTokenAddress).transfer(USER, INITIAL_DEPOSIT);
            } else {
                // Give some fromTokens (WETH) for USER
                IWETH(payable(fromTokenAddress)).deposit{value: INITIAL_DEPOSIT}();
                IWETH(payable(fromTokenAddress)).transfer(USER, INITIAL_DEPOSIT);
            }
        }
    }

    // MODIFIERS SECTION

    modifier whitelistSwapPair(address fromToken, address toToken) {
        vm.prank(switchlaneOwner);
        switchlaneExposed.whitelistSwapPair(fromToken, toToken);
        _;
    }

    modifier whitelistChain(uint64 destinationChain) {
        vm.prank(switchlaneOwner);
        switchlaneExposed.whitelistChain(destinationChain);
        _;
    }

    modifier addPriceFeedToToken(address token, address priceFeed) {
        vm.prank(switchlaneOwner);
        switchlaneExposed.addPriceFeedUsdAddressToToken(token, priceFeed);
        _;
    }

    modifier whitelistReceiveToken(address token) {
        vm.prank(switchlaneOwner);
        switchlaneExposed.allowlistReceiveToken(token);
        _;
    }

    // TESTS SECTION

    function testBalance() public {
        uint256 balance = IWETH(payable(fromTokenAddress)).balanceOf(USER);

        assertEq(balance, INITIAL_DEPOSIT);
    }

    function testWithdrawTokenRevertsIfNotCalledByOwner() public {
        vm.prank(USER);
        vm.expectRevert("Only callable by owner");
        switchlaneExposed.withdrawToken(USER, fromTokenAddress);
    }

    function testWithdrawTokenRevertsIfBalanceOfTokenIsZero() public {
        vm.prank(switchlaneOwner);
        vm.expectRevert(Switchlane.NothingToWithdraw.selector);
        switchlaneExposed.withdrawToken(USER, fromTokenAddress);
    }

    function testWithdrawToken() public {
        vm.prank(USER);
        IWETH(payable(fromTokenAddress)).transfer(address(switchlaneExposed), INITIAL_DEPOSIT);

        assertEq(IWETH(payable(fromTokenAddress)).balanceOf(USER), 0);

        vm.prank(switchlaneOwner);
        switchlaneExposed.withdrawToken(switchlaneOwner, fromTokenAddress);

        assertEq(IWETH(payable(fromTokenAddress)).balanceOf(switchlaneOwner), INITIAL_DEPOSIT);
    }

    function testCalculateLinkFees()
        public
        whitelistSwapPair(fromTokenAddress, toTokenAddress)
        whitelistChain(ARBITRUM_DESTINATION_CHAIN)
    {
        vm.prank(switchlaneOwner);
        uint256 linkFees =
            switchlaneExposed.calculateLinkFees(fromTokenAddress, toTokenAddress, 1e18, ARBITRUM_DESTINATION_CHAIN);

        console.log("LINK used on CCIP: ", linkFees);
        assert(linkFees > 0);
    }

    // Test it on mainnet
    function testCalculateProtocolFeesOnMainnet()
        public
        whitelistSwapPair(fromTokenAddress, toTokenAddress)
        whitelistChain(ARBITRUM_DESTINATION_CHAIN)
        addPriceFeedToToken(toTokenAddress, fees.linkPriceFeedAddress) // This is like this because I'm using LINK as toToken
        addPriceFeedToToken(fromTokenAddress, wethPriceFeedMainnet)
    {
        uint256 AMOUNT_WETH_SENT = 1e18;
        uint256 EXPECTED_TO_TOKEN_AMOUNT = 100e18;

        vm.prank(USER);
        uint256 feesInUsd = switchlaneExposed.calculateProtocolFees(
            fromTokenAddress, toTokenAddress, AMOUNT_WETH_SENT, EXPECTED_TO_TOKEN_AMOUNT, ARBITRUM_DESTINATION_CHAIN
        );

        console.log("PROTOCOL FEES IN USD: ", feesInUsd);
        assert(feesInUsd > 0);
    }

    // As CCIP on mainnet requires special access, this function must be tested on testnets
    // From Mumbai to Sepolia
    // SLN ---> CCIP-BnM
    function testSwitchlaneExactInputSendSLNTokenReceiveCCIPBnM()
        public
        whitelistSwapPair(fromTokenAddress, toTokenAddress)
        whitelistSwapPair(fromTokenAddress, linkAddress)
        whitelistChain(SEPOLIA_DESTINATION_CHAIN)
        addPriceFeedToToken(toTokenAddress, ccipBnMPriceFeedMumbai)
        addPriceFeedToToken(fromTokenAddress, slnPriceFeedMumbai)
        whitelistReceiveToken(fromTokenAddress)
    {
        uint24 maxTolerance = 5000;
        uint256 minimumReceiveAmount = switchlaneExposed.calculateMinimumOutAmount(
            fromTokenAddress, toTokenAddress, maxTolerance, INITIAL_DEPOSIT, SEPOLIA_DESTINATION_CHAIN
        );
        vm.startPrank(USER);

        if (block.chainid == MUMBAI_CHAINID) {
            ISLN(fromTokenAddress).approve(address(switchlaneExposed), INITIAL_DEPOSIT);
        } else {
            IWETH(payable(fromTokenAddress)).approve(address(switchlaneExposed), INITIAL_DEPOSIT);
        }

        switchlaneExposed.switchlaneExactInput(
            USER,
            USER,
            fromTokenAddress,
            toTokenAddress,
            SEPOLIA_DESTINATION_CHAIN,
            INITIAL_DEPOSIT,
            minimumReceiveAmount
        );

        vm.stopPrank();
    }

    // As CCIP on mainnet requires special access, this function must be tested on testnets
    // From Mumbai to Sepolia
    // SLN ---> CCIP-BnM
    function testSwitchlaneExactOutputSendSLNTokenReceiveCCIPBnM()
        public
        whitelistSwapPair(fromTokenAddress, toTokenAddress)
        whitelistSwapPair(fromTokenAddress, linkAddress)
        whitelistChain(SEPOLIA_DESTINATION_CHAIN)
        addPriceFeedToToken(toTokenAddress, ccipBnMPriceFeedMumbai)
        addPriceFeedToToken(fromTokenAddress, slnPriceFeedMumbai)
        whitelistReceiveToken(fromTokenAddress)
    {
        uint256 expectedOutputAmount = 3e17; // Adjust this to actual price data

        vm.startPrank(USER);

        if (block.chainid == MUMBAI_CHAINID) {
            ISLN(fromTokenAddress).approve(address(switchlaneExposed), INITIAL_DEPOSIT);
        } else {
            IWETH(payable(fromTokenAddress)).approve(address(switchlaneExposed), INITIAL_DEPOSIT);
        }

        switchlaneExposed.switchlaneExactOutput(
            USER,
            USER,
            fromTokenAddress,
            toTokenAddress,
            SEPOLIA_DESTINATION_CHAIN,
            expectedOutputAmount,
            INITIAL_DEPOSIT
        );

        vm.stopPrank();
    }

    function testSwapExactInputSingle()
        public
        whitelistSwapPair(fromTokenAddress, toTokenAddress)
        whitelistReceiveToken(fromTokenAddress)
        addPriceFeedToToken(fromTokenAddress, wethPriceFeedMainnet)
        addPriceFeedToToken(toTokenAddress, fees.linkPriceFeedAddress)
        whitelistChain(ARBITRUM_DESTINATION_CHAIN)
    {
        uint24 maxTolerance = 5000;
        uint256 minimumOutAmount = switchlaneExposed.calculateMinimumOutAmount(
            fromTokenAddress, toTokenAddress, maxTolerance, INITIAL_DEPOSIT, ARBITRUM_DESTINATION_CHAIN
        );

        vm.startPrank(USER);

        IERC20(fromTokenAddress).approve(address(switchlaneExposed), INITIAL_DEPOSIT);

        switchlaneExposed.receiveTokens(USER, fromTokenAddress, INITIAL_DEPOSIT);

        uint256 actualAmountOut =
            switchlaneExposed.swapExactInputSingle(fromTokenAddress, toTokenAddress, INITIAL_DEPOSIT, minimumOutAmount);

        vm.stopPrank();

        uint256 expectedBalanceAfterSwap = 0;
        uint256 actualBalanceAfterSwap = IERC20(fromTokenAddress).balanceOf(USER);

        assertEq(expectedBalanceAfterSwap, actualBalanceAfterSwap);

        uint256 expectedMinimumBalanceToTokenAfterSwap = minimumOutAmount;

        assert(actualAmountOut >= expectedMinimumBalanceToTokenAfterSwap);

        uint256 actualBalanceSwitchlaneAfterSwap = IERC20(toTokenAddress).balanceOf(address(switchlaneExposed));

        assert(actualBalanceSwitchlaneAfterSwap == actualAmountOut);
    }

    function testSwapExactOutputSingle()
        public
        whitelistSwapPair(fromTokenAddress, toTokenAddress)
        whitelistReceiveToken(fromTokenAddress)
        addPriceFeedToToken(fromTokenAddress, wethPriceFeedMainnet)
        addPriceFeedToToken(toTokenAddress, fees.linkPriceFeedAddress)
        whitelistChain(ARBITRUM_DESTINATION_CHAIN)
    {
        uint256 exactOutput = 100e18;
        uint24 maxTolerance = 5000;
        uint256 maximumInAmount = switchlaneExposed.calculateMaximumInAmount(
            fromTokenAddress, toTokenAddress, maxTolerance, exactOutput, ARBITRUM_DESTINATION_CHAIN
        );

        console.log(maximumInAmount);

        vm.startPrank(USER);

        IERC20(fromTokenAddress).balanceOf(USER);

        IERC20(fromTokenAddress).approve(address(switchlaneExposed), maximumInAmount);

        switchlaneExposed.receiveTokens(USER, fromTokenAddress, maximumInAmount);

        uint256 actualAmountIn =
            switchlaneExposed.swapExactOutputSingle(fromTokenAddress, toTokenAddress, exactOutput, maximumInAmount);

        vm.stopPrank();

        assert(actualAmountIn <= maximumInAmount);

        uint256 expectedBalanceAfterSwap = INITIAL_DEPOSIT - maximumInAmount; // This need to change not used tokens must be refunded
        uint256 actualBalanceAfterSwap = IERC20(fromTokenAddress).balanceOf(USER);

        assertEq(expectedBalanceAfterSwap, actualBalanceAfterSwap);

        uint256 balanceOfSwitchlane = IERC20(toTokenAddress).balanceOf(address(switchlaneExposed));

        assertEq(balanceOfSwitchlane, exactOutput);
    }
}
