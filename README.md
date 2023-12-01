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