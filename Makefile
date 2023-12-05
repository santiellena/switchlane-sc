-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

FORK_TEST_PATH := "test/fork/Switchlane.t.sol"

UNIT_TEST_PATH := "test/unit/Switchlane.t.sol"

install :
	@forge install transmissions11/solmate --no-commit && forge install smartcontractkit/chainlink --no-commit && forge install OpenZeppelin/openzeppelin-contracts --no-commit && npm install

anvil:; anvil

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(ANVIL_KEY) --broadcast

NETWORK_FORK_ARGS := --fork-url $(MUMBAI_FORK_URL)

ifeq ($(findstring --fork polygon,$(ARGS)), --fork polygon)
	NETWORK_FORK_ARGS := --fork-url $(POLYGON_FORK_URL)  
endif

ifeq ($(findstring --fork mumbai,$(ARGS)), --fork mumbai)
	NETWORK_FORK_ARGS := --fork-url $(MUMBAI_FORK_URL) 
endif

ifeq ($(findstring --fork mainnet,$(ARGS)), --fork mainnet)
	NETWORK_FORK_ARGS := --fork-url $(MAINNET_FORK_URL) 
endif

ifeq ($(findstring --fork sepolia,$(ARGS)), --fork sepolia)
	NETWORK_FORK_ARGS := --fork-url $(SEPOLIA_FORK_URL) 
endif

ifeq ($(findstring --network mainnet,$(ARGS)),--network mainnet)
	NETWORK_ARGS := --rpc-url $(MAINNET_FORK_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

ifeq ($(findstring --network polygon,$(ARGS)),--network polygon)
	NETWORK_ARGS := --rpc-url $(POLYGON_FORK_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

ifeq ($(findstring --network mumbai,$(ARGS)),--network mumbai)
	NETWORK_ARGS := --rpc-url $(MUMBAI_FORK_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

test:
	@forge test $(NETWORK_FORK_ARGS) --match-path $(FORK_TEST_PATH) -vvv

testMatch:
	@forge test $(NETWORK_FORK_ARGS) --match-test $(ARGS) --match-path $(FORK_TEST_PATH) -vvvvv

unit:
	@forge test --match-path $(UNIT_TEST_PATH) -vvv

deploy:
	@forge script script/DeploySwitchlane.s.sol:DeploySwitchlane $(NETWORK_ARGS)

coverage: # To use this you need to have lcov and genhtml installed ($ sudo apt install lcov; sudo apt install genhtml)
	@forge coverage --report lcov
	@lcov --remove lcov.info  -o lcov.info 'test/*' 'script/*'
	@genhtml -o report --branch-coverage ./lcov.info