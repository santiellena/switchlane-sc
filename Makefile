-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

FORK_TEST_PATH := "test/fork/Switchlane.t.sol"

install :
	forge install transmissions11/solmate --no-commit && forge install smartcontractkit/chainlink --no-commit && forge install OpenZeppelin/openzeppelin-contracts --no-commit && npm install

anvil:; anvil

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(ANVIL_KEY) --broadcast

NETWORK_FORK_ARGS := --fork-url $(MAINNET_FORK_URL)

ifeq ($(findstring --fork polygon,$(ARGS)), --fork polygon)
	NETWORK_FORK_ARGS := --fork-url $(POLYGON_FORK_URL)  
endif

ifeq ($(findstring --fork mumbai,$(ARGS)), --fork mumbai)
	NETWORK_FORK_ARGS := --fork-url $(MUMBAI_FORK_URL) 
endif

test:
	forge test $(NETWORK_FORK_ARGS) --match-path $(FORK_TEST_PATH) -vvvvv

env: 
	touch .env && echo -e "ANVIL_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80\nPRIVATE_KEY=\nPOLYGON_FORK_URL=\nMAINNET_FORK_URL=\nMUMBAI_FORK_URL=" > ./.env
