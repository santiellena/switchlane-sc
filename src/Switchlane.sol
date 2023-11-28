// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
pragma abicoder v2;

// Chainlink CCIP imports
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

// Chainlink imports
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

// Uniswap imports
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

// OpenZeppelin imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    // There are 3 fee levels: 0.05% (500), 0.3% (3000) & 1% (10000).
    // Being 3000 the recommended value for most of pools
    uint24 public poolFee;

    /**
     *  ERRORS SECTION
     */

    error NotEnoughLinkBalance(uint256 currentBalance, uint256 calculatedFees);
    error NothingToWithdraw(address);
    error DestinationChainNotWhiteListed(uint64 destinationChainSelector);
    error TokenOnChainNotWhiteListed(uint64 destinationChainSelector, address token);
    error ReceiveTokenNotWhiteListed(address token);
    error NotEnoughTokenBalance(address sender, address token, uint256 amount);
    error SwapPairNotWhiteListed(address fromToken, address toToken);

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
            revert DestinationChainNotWhiteListed(_destinationChainSelector);
        }
        _;
    }

    modifier onlyWhiteListedTokenOnChain(uint64 _destinationChainSelector, address _token) {
        if (!whiteListedTokensOnChains[_destinationChainSelector][_token]) {
            revert TokenOnChainNotWhiteListed(_destinationChainSelector, _token);
        }
        _;
    }

    modifier onlyWhiteListedReceiveTokens(address _token) {
        if (!whiteListedReceiveTokens[_token]) {
            revert ReceiveTokenNotWhiteListed(_token);
        }
        _;
    }

    modifier onlyWhiteListedSwapPair(address fromToken, address toToken) {
        if (!whiteListedSwapPair[fromToken][toToken]) {
            revert SwapPairNotWhiteListed(fromToken, toToken);
        }
        _;
    }

    modifier hasEnoughBalance(address sender, address token, uint256 amount) {
        if (IERC20(token).balanceOf(sender) < amount) {
            revert NotEnoughTokenBalance(sender, token, amount);
        }
        _;
    }

    // CONSTRUCTOR

    constructor(address _router, address _linkToken, uint24 _poolFee, address _swapRouter) {
        router = IRouterClient(_router);
        linkToken = LinkTokenInterface(_linkToken);
        poolFee = _poolFee;
        swapRouter = ISwapRouter(_swapRouter);
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
    function _trasnferTokens(uint64 _destinationChainSelector, address _receiver, address _token, uint256 _amount)
        internal
        onlyWhiteListedChain(_destinationChainSelector)
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
            revert NotEnoughLinkBalance(balanceOfContract, fees);
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
     * @param token address of the erc 20 token sent and used to pay fees
     * @param amount amount of the erc 20 token sent and used to pay fees
     */
    function _receiveTokens(address token, uint256 amount)
        internal
        onlyWhiteListedReceiveTokens(token)
        hasEnoughBalance(msg.sender, token, amount)
    {
        IERC20(token).approve(address(this), amount);
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function _swapExactInputSingle(address fromToken, address toToken, uint256 amountIn, uint256 amountOutMinimum)
        internal
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

        if (amount == 0) revert NothingToWithdraw(address(this));

        IERC20(_token).transfer(_beneficiary, amount);
    }

    /**
     *  EXTERNAL FUNCTIONS SECTION
     */

    function switchlane() external {}

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
}
