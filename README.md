# Switchlane

## Quickstart

#### Requirements:

First of all, install Make:

{% embed url="https://www.geeksforgeeks.org/how-to-install-make-on-ubuntu/" %}

To use this code, you need to have installed [foundry](https://github.com/crisgarner/awesome-foundry) & [npm](https://nodejs.org/en).

To check if you have them installed:

```bash
# In case you have them installed you will see the versions
$ forge --version
$ npm --version
```

The Makefile has the _install_ command to download and install everything you need to start testing and developing.

```bash
$ make install
```

Before starting the development or testing you need to set up your environment variables:

1. Create your _.env_ file
2. Put your own private key (not needed for testing)
3. Go to [Chiannodes](https://app.chainnodes.org/) or to [Alchemy](https://www.alchemy.com/) to get your RPC URLs to connect and get the fork data.

As Switchlane depends directly on other smart contracts most of its functions (if not all of them) need interactions with the blockchain. Additionally, mocking this complex systems is completely impossible, so all tests are fork tests.

#### Tests:

To run fork tests, located at _test/fork/Switchlane.t.sol_:

```bash
$ make test
```

To run unit tests, located at _test/unit/Switchlane.t.sol_:

```bash
$ make unit
```

#### Deploy:

To deploy the Switchlane contract to start interacting with it:

```bash
# To deploy on Anvil
$ make deploy

# To deploy on Polygon
$ make deploy --network polygon

# To deploy on Mumbai
$ make deploy --network mumbai

# To deploy on Mainnet
$ make deploy --network mainnet
```
