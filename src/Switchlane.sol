// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

using ECDSA for bytes32;

contract Switchlane is OwnerIsCreator {
    IRouterClient router;
    LinkTokenInterface linkToken;

    mapping(uint64 => bool) public whiteListedChains;
    mapping(uint64 => mapping(address => bool)) whiteListedTokensOnChains;
    mapping(address => bool) whiteListedReceiveTokens;

    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error NothingToWithdraw(address);
    error DestinationChainNotWhiteListed(uint64 destinationChainSelector);
    error TokenOnChainNotWhiteListed(uint64 destinationChainSelector, address token);
    error ReceiveTokenNotWhiteListed(address token);

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

    constructor(address _router, address _linkToken) {
        router = IRouterClient(_router);
        linkToken = LinkTokenInterface(_linkToken);
    }

    /**
     *
     * @param _destinationChainSelector identificator of the chain in which tokens will be received
     * @param _receiver the address that will receive the tokens
     * @param _token address of the token
     * @param _amount amount of token to be sended
     */
    function trasnferTokens(uint64 _destinationChainSelector, address _receiver, address _token, uint256 _amount)
        external
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
            revert NotEnoughBalance(balanceOfContract, fees);
        }

        linkToken.approve(address(router), fees);

        IERC20(_token).approve(address(router), _amount);

        messageId = router.ccipSend(_destinationChainSelector, message);

        emit TokensTransferred(
            messageId, _destinationChainSelector, _receiver, _token, _amount, address(linkToken), fees
        );
    }

    function withdrawToken(address _beneficiary, address _token) public onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));

        if (amount == 0) revert NothingToWithdraw(address(this));

        IERC20(_token).transfer(_beneficiary, amount);
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
}
