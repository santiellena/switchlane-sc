# Switchlane

## Quickstart

The Makefile has the *install* command to download and install everything you need to start testing and developing.

```bash
$ make install
```

Before starting the development or testing you need to set up your environment variables:
1) Create your *.env* file
2) Put your own private key (not needed for testing)
3) Go to [Chiannodes](https://app.chainnodes.org/) or to [Alchemy](https://www.alchemy.com/) to get yout RPC URLs to connect and get the fork data.

As Switchlane depends directly on other smart contracts most of its functions (if not all of them) need interactions with the blockchain. Additionally, mocking this complex systems is completely impossible, so all tests are fork tests.

To run fork tests, located on *test/fork/Switchlane.t.sol*:

```bash
$ make test
```

### Considerations:

- When switchlaneExactInput or  switchlaneExactOutput are executed, if the 'fromToken' is the same as the 'toToken' then one swap does not need to be made (just one to get link tokens to pay fees).

- After the execution of the previously mentioned functions, the user must execute a third transaction: erc20.approve(0).

- If the user is sending LINK and expects LINK to be received, none swap must be made.

- If the user is sending LINK and expects to receive other token, just one swap must be made (from LINK to that other token, leaving an amount to pay fees).

- If the user is sending other token and expects to receive LINK, just one swap must be made (the whole amount of that token into LINK)