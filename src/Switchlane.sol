// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
pragma abicoder v2;

// Chainlink CCIP imports
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

// Chainlink imports
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// Uniswap imports
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// OpenZeppelin imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

using ECDSA for bytes32;

contract Switchlane is OwnerIsCreator {
    /**
     *  STATE VARIABLES SECTION
     */

    IRouterClient private router;
    LinkTokenInterface private linkToken;
    ISwapRouter private swapRouter;

    mapping(uint64 => bool) public whiteListedChains;
    mapping(uint64 => mapping(address => bool)) public whiteListedTokensOnChains;
    mapping(address => bool) public whiteListedReceiveTokens;
    // On the white list of swap pairs is important to know the direction of the swap.
    // Swapping from LINK to USDC could be allowed but not necessarily from USDC to LINK.
    mapping(address => mapping(address => bool)) public whiteListedSwapPair;
    mapping(address => address) private tokenAddressToPriceFeedUsdAddress;

    // There are 3 fee levels: 0.05% (500), 0.3% (3000) & 1% (10000).
    // Being 3000 the recommended value for most of pools
    uint24 public poolFee;

    uint256 private linkMarginFee;

    // Price feed returns a number with 8 decimals and the whole system works with 18
    int256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant PERCENTAGE_PRECISION = 1e22;

    /**
     *  ERRORS SECTION
     */

    error NotEnoughLinkBalance();
    error NothingToWithdraw();
    error DestinationChainNotWhiteListed();
    error TokenOnChainNotWhiteListed();
    error ReceiveTokenNotWhiteListed();
    error NotEnoughTokenBalance();
    error SwapPairNotWhiteListed();
    error UnreachedMinimumAmount();
    error NotEnoughTokensToPayFees();
    error MustBeMoreThanZero();
    error MustHaveAssociatedPriceFeed();

    /**
     *  EVENTS SECTION
     */

    /**
     *
     * @param messageId The unique ID of the message.
     * @param destinationChainSelector The chain selector of the destination chain.
     * @param receiver The address of the receiver on the destination chain.
     * @param token The token address that was transferred.
     * @param tokenAmount The token amount that was transferred.
     * @param feeToken The token address used to pay CCIP fees.
     * @param fees The fees paid for sending the message.
     */
    event TokensTransferred(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    /**
     *  MODIFIERS SECTION
     */

    modifier onlyWhiteListedChain(uint64 _destinationChainSelector) {
        if (!whiteListedChains[_destinationChainSelector]) {
            revert DestinationChainNotWhiteListed();
        }
        _;
    }

    modifier onlyWhiteListedTokenOnChain(uint64 _destinationChainSelector, address _token) {
        if (!whiteListedTokensOnChains[_destinationChainSelector][_token]) {
            revert TokenOnChainNotWhiteListed();
        }
        _;
    }

    modifier onlyWhiteListedReceiveTokens(address _token) {
        if (!whiteListedReceiveTokens[_token]) {
            revert ReceiveTokenNotWhiteListed();
        }
        _;
    }

    modifier onlyWhiteListedSwapPair(address fromToken, address toToken) {
        if (!whiteListedSwapPair[fromToken][toToken]) {
            revert SwapPairNotWhiteListed();
        }
        _;
    }

    modifier hasEnoughBalance(address sender, address token, uint256 amount) {
        if (IERC20(token).balanceOf(sender) < amount) {
            revert NotEnoughTokenBalance();
        }
        _;
    }

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert MustBeMoreThanZero();
        }
        _;
    }

    modifier hasPriceFeedAddressAssociated(address token) {
        if (tokenAddressToPriceFeedUsdAddress[token] == address(0)) {
            revert MustHaveAssociatedPriceFeed();
        }
        _;
    }

    // CONSTRUCTOR

    constructor(
        address _router,
        address _linkToken,
        uint24 _poolFee,
        address _swapRouter,
        uint256 _linkMarginFee,
        address _linkPriceFeedAddress
    ) {
        router = IRouterClient(_router);
        linkToken = LinkTokenInterface(_linkToken);
        poolFee = _poolFee;
        swapRouter = ISwapRouter(_swapRouter);
        linkMarginFee = _linkMarginFee;
        tokenAddressToPriceFeedUsdAddress[_linkToken] = _linkPriceFeedAddress;
    }

    /**
     *   INTERNAL FUNCTIONS SECTION
     */

    /**
     *
     * @param _destinationChainSelector identificator of the chain in which tokens will be received
     * @param _receiver the address that will receive the tokens
     * @param _token address of the token
     * @param _amount amount of token to be sended
     */
    function _transferTokens(uint64 _destinationChainSelector, address _receiver, address _token, uint256 _amount)
        internal
        onlyWhiteListedChain(_destinationChainSelector)
        moreThanZero(_amount)
        onlyOwner
        returns (bytes32 messageId)
    {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({token: _token, amount: _amount});
        tokenAmounts[0] = tokenAmount;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: "",
            tokenAmounts: tokenAmounts,
            /**
             * - "strict" is used for strict sequencing
             *  -  it will prevent any following messages from the same sender from
             *  being processed until the current message is successfully executed.
             *  DOCS: https://docs.chain.link/ccip/best-practices#sequencing
             */
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0, strict: false})),
            feeToken: address(linkToken)
        });

        uint256 fees = router.getFee(_destinationChainSelector, message);

        uint256 balanceOfContract = linkToken.balanceOf(address(this));

        if (fees > balanceOfContract) {
            revert NotEnoughLinkBalance();
        }

        linkToken.approve(address(router), fees);

        IERC20(_token).approve(address(router), _amount);

        messageId = router.ccipSend(_destinationChainSelector, message);

        emit TokensTransferred(
            messageId, _destinationChainSelector, _receiver, _token, _amount, address(linkToken), fees
        );
    }

    /**
     *
     * @param sender address of the erc 20 tokens owner
     * @param token address of the erc 20 token sent and used to pay fees
     * @param amount amount of the erc 20 token sent and used to pay fees
     */
    function _receiveTokens(address sender, address token, uint256 amount)
        internal
        onlyWhiteListedReceiveTokens(token)
        moreThanZero(amount)
        hasEnoughBalance(sender, token, amount)
    {
        IERC20(token).transferFrom(sender, address(this), amount);
    }

    function _swapExactInputSingle(address fromToken, address toToken, uint256 amountIn, uint256 amountOutMinimum)
        internal
        onlyWhiteListedSwapPair(fromToken, toToken)
        moreThanZero(amountIn)
        moreThanZero(amountOutMinimum)
        returns (uint256 amountOut)
    {
        linkToken.approve(address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: fromToken,
            tokenOut: toToken,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        amountOut = swapRouter.exactInputSingle(params);
    }

    function _swapExactOutputSingle(address fromToken, address toToken, uint256 amountOut, uint256 amountInMaximum)
        internal
        onlyWhiteListedSwapPair(fromToken, toToken)
        moreThanZero(amountOut)
        moreThanZero(amountInMaximum)
        returns (uint256 amountIn)
    {
        linkToken.approve(address(swapRouter), amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: fromToken,
            tokenOut: toToken,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0
        });

        amountIn = swapRouter.exactOutputSingle(params);

        if (amountIn < amountInMaximum) {
            linkToken.approve(address(swapRouter), 0);
            linkToken.transfer(address(this), amountInMaximum - amountIn);
        }
    }

    /**
     *  PUBLIC FUNCTIONS SECTION
     */

    function withdrawToken(address _beneficiary, address _token) public onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));

        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).transfer(_beneficiary, amount);
    }

    function calculateLinkFees(
        address fromToken,
        address toToken,
        uint256 expectedAmountToToken,
        uint64 destinationChain
    )
        public
        view
        moreThanZero(expectedAmountToToken)
        onlyWhiteListedSwapPair(fromToken, toToken)
        onlyWhiteListedChain(destinationChain)
        returns (uint256 linkFee)
    {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: toToken, amount: expectedAmountToToken});
        tokenAmounts[0] = tokenAmount;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(msg.sender),
            data: "",
            tokenAmounts: tokenAmounts,
            /**
             * - "strict" is used for strict sequencing
             *  -  it will prevent any following messages from the same sender from
             *  being processed until the current message is successfully executed.
             *  DOCS: https://docs.chain.link/ccip/best-practices#sequencing
             */
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0, strict: false})),
            feeToken: address(linkToken)
        });

        // ccipFees is the amount of LINK tokens that the tx will cost
        uint256 ccipFees = router.getFee(destinationChain, message);

        linkFee = ccipFees + linkMarginFee;
    }

    function calculateProtocolFees(
        address fromToken,
        address toToken,
        uint256 amountFromToken,
        uint256 expectedAmountToToken,
        uint64 destinationChain
    )
        public
        view
        moreThanZero(amountFromToken)
        moreThanZero(expectedAmountToToken)
        onlyWhiteListedSwapPair(fromToken, toToken)
        onlyWhiteListedChain(destinationChain)
        returns (uint256 fees)
    {
        uint256 linkFee = calculateLinkFees(fromToken, toToken, expectedAmountToToken, destinationChain);
        uint256 linkFeesInUsd = getTokenUsdValue(address(linkToken), linkFee);

        uint256 fromTokenFees = (amountFromToken * uint256(poolFee) * PRECISION) / PERCENTAGE_PRECISION;

        uint256 fromTokenFeesInUsd = getTokenUsdValue(fromToken, fromTokenFees);

        fees = linkFeesInUsd + fromTokenFeesInUsd;
    }

    function getTokenUsdValue(address token, uint256 amount) public view returns (uint256 amountInUsd) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(tokenAddressToPriceFeedUsdAddress[token]);

        /**
         * latestRoundData returns:
         *
         *   - uint80 roundId,
         *   - int256 answer,
         *   - uint256 startedAt,
         *   - uint256 updatedAt,
         *   - uint80 answeredInRound
         */

        (, int256 price,,,) = priceFeed.latestRoundData();

        amountInUsd = uint256(uint256(price * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /**
     *  EXTERNAL FUNCTIONS SECTION
     */

    /**
     *
     * @param sender address that is sending the tokens
     * @param receiver address that is receiving the tokens
     * @param fromToken token being sent
     * @param toToken token being received
     * @param destinationChain chain where the toToken will be sent
     * @param amount total amount of tokens of the 'fromToken'
     * @param minimumReceiveAmount minimum expected amount to be sent to the receiver (optional)
     */
    function switchlaneExactInput(
        address sender,
        address receiver,
        address fromToken,
        address toToken,
        uint64 destinationChain,
        uint256 amount,
        uint256 minimumReceiveAmount
    ) external onlyOwner moreThanZero(amount) moreThanZero(minimumReceiveAmount) {
        /**
         * Steps:
         *      1)  Calculate fees
         *      2)  Collect/Receive ERC20 tokens
         *      3)  Swap exact output to get the tokens for fees and profit
         *      4)  Swap exact input with left ERC20 tokens from step 2
         *          to send tokens to the receiver through CCIP
         *      5)  Initiate CCIP tx
         *      6)  Emit event on success
         */

        _receiveTokens(sender, fromToken, amount);

        /**
         * amountInMaximum = _calculateAmountInMaximum();
         *
         *         This previous funtion can be used to calculate the maximum amount of fromTokens
         *         that are expected to be paid given price feeds data. So we are not paying a high price for the
         *         token because of an eventual imbalance of the liquidity pool.
         *
         *         This can be fixed with the implementation of the minimumReceiveAmount parameter.
         */

        if (fromToken == address(linkToken) && toToken == address(linkToken)) {
            _transferTokens(destinationChain, receiver, toToken, amount);
        } else {
            uint256 linkFee = calculateLinkFees(fromToken, toToken, minimumReceiveAmount, destinationChain);
            // Amount of the 'fromToken' used to pay fees
            uint256 amountIn = _swapExactOutputSingle(fromToken, address(linkToken), linkFee, 0);

            uint256 leftAmount = amount - amountIn;

            // Amount of the 'toTokens' received from the swap ready to be sent through CCIP
            uint256 amountOut;

            // This conditional statement lets the protocol allow the sending of the same
            // 'fromToken' and 'toToken'
            if (fromToken != toToken) {
                amountOut = _swapExactInputSingle(fromToken, toToken, leftAmount, 0);
                if (amountOut < minimumReceiveAmount) {
                    revert UnreachedMinimumAmount();
                }
            } else {
                amountOut = leftAmount;
            }

            _transferTokens(destinationChain, receiver, toToken, amountOut);
        }

        // After this function for security reasons the user must send token.approve(0);
    }

    /**
     *
     * @param sender address that is sending the tokens
     * @param receiver address that is receiving the tokens
     * @param fromToken token being sent
     * @param toToken token being received
     * @param destinationChain chain where the toToken will be sent
     * @param expectedOutputAmount expected amount to be sent to the receiver of 'toToken'
     * @param amount amount of the 'fromToken' used
     */
    function switchlaneExactOutput(
        address sender,
        address receiver,
        address fromToken,
        address toToken,
        uint64 destinationChain,
        uint256 expectedOutputAmount,
        uint256 amount
    ) external onlyOwner moreThanZero(amount) moreThanZero(expectedOutputAmount) {
        /**
         * Steps:
         *      1)  Collect/Receive ERC20 tokens
         *      2)  Swap exact output to get the tokens to send tokens
         *          to the receiver through CCIP
         *      3)  Swap exact input with left ERC20 tokens from step 2
         *          for fees and profit
         *      4)  Initiate CCIP tx
         *      5)  Emit event on success
         */

        _receiveTokens(sender, fromToken, amount);

        uint256 linkFee = calculateLinkFees(fromToken, toToken, expectedOutputAmount, destinationChain);

        // This conditional statement lets the protocol allow the sending of the same
        // 'fromToken' and 'toToken'
        uint256 leftTokens;

        if (fromToken == address(linkToken) && toToken == address(linkToken)) {
            // Check if both tokens are LINK so zero swaps are executed
            leftTokens = amount - linkFee;

            if (leftTokens < expectedOutputAmount) {
                revert NotEnoughTokensToPayFees();
            }
        } else if (fromToken != toToken) {
            uint256 amountIn = _swapExactOutputSingle(fromToken, toToken, expectedOutputAmount, amount);

            leftTokens = amount - amountIn;

            uint256 amountOut = _swapExactInputSingle(fromToken, address(linkToken), leftTokens, 0);

            if (amountOut < linkFee) {
                revert NotEnoughTokensToPayFees();
            }
        } else {
            uint256 amountIn = _swapExactOutputSingle(fromToken, address(linkToken), linkFee, 0);

            leftTokens = amount - amountIn;

            if (leftTokens < expectedOutputAmount) {
                revert NotEnoughTokensToPayFees();
            }
        }

        _transferTokens(destinationChain, receiver, toToken, expectedOutputAmount);
    }

    /**
     *
     * @notice allow a chain to receive tokens
     */
    function whitelistChain(uint64 _destinationChainSelector) external onlyOwner {
        whiteListedChains[_destinationChainSelector] = true;
    }

    /**
     *
     * @notice deny a chain to receive tokens
     */
    function denylistChain(uint64 _destinationChainSelector) external onlyOwner {
        whiteListedChains[_destinationChainSelector] = false;
    }

    /**
     *
     * @notice allow a token to be sent on a specific chain
     */
    function whitelistTokenOnChain(uint64 _destinationChainSelector, address _token) external onlyOwner {
        whiteListedTokensOnChains[_destinationChainSelector][_token] = true;
    }

    /**
     *
     * @notice deny a token to be sent on a specific chain
     */
    function denylistTokenOnChain(uint64 _destinationChainSelector, address _token) external onlyOwner {
        whiteListedTokensOnChains[_destinationChainSelector][_token] = false;
    }

    /**
     *
     * @notice allow a token to be received
     */
    function allowlistReceiveToken(address _token) external onlyOwner {
        whiteListedReceiveTokens[_token] = true;
    }

    /**
     *
     * @notice deny a token to be received
     */
    function denylistReceiveToken(address _token) external onlyOwner {
        whiteListedReceiveTokens[_token] = false;
    }

    /**
     *
     * @notice allow a swap pair to be swapped
     */
    function whitelistSwapPair(address fromToken, address toToken) external onlyOwner {
        whiteListedSwapPair[fromToken][toToken] = true;
    }

    /**
     *
     * @notice deny a swap pair to be swapped
     */
    function denylistSwapPair(address fromToken, address toToken) external onlyOwner {
        whiteListedSwapPair[fromToken][toToken] = false;
    }

    function changePoolFee(uint24 newPoolFee) external onlyOwner {
        poolFee = newPoolFee;
    }

    /**
     * @notice adds a price feed address that allows the system to get the usd value to calculate fees
     *
     * @param token address of a token that can be sent (fromToken)
     * @param priceFeed address of the price feed contract token/USD
     */
    function addPriceFeedUsdAddressToToken(address token, address priceFeed) external onlyOwner {
        tokenAddressToPriceFeedUsdAddress[token] = priceFeed;
    }

    /**
     * @notice removes a price feed address that allows the system to get the usd value to calculate fees
     *
     * @param token address of a token that can be sent (fromToken)
     */
    function removePriceFeedUsdAddressToToken(address token) external onlyOwner {
        tokenAddressToPriceFeedUsdAddress[token] = address(0);
    }

    /**
     *  EXTERNAL & VIEW FUNCTIONS SECTION
     */

    function getRouterAddress() external view returns (address) {
        return address(router);
    }

    function getLinkTokenAddress() external view returns (address) {
        return address(linkToken);
    }

    function getSwapRouter() external view returns (address) {
        return address(swapRouter);
    }

    function getTokenPriceFeedAddress(address token) external view onlyOwner returns (address) {
        return tokenAddressToPriceFeedUsdAddress[token];
    }
}
