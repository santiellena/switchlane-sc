// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct Fees {
        uint256 linkFee;
        uint24 poolFee;
    }

    struct NetworkConfig {
        address routerAddress;
        address linkAddress;
        address swapRouterAddress;
        Fees fees;
        uint256 deployerKey;
        address wethTokenAddress;
        address usdcTokenAddress;
    }

    uint256 public constant MUMBAI_CHAINID = 80001;
    uint256 public constant POLYGON_CHAINID = 137;
    uint256 public constant MAINNET_CHAINID = 1;

    uint24 public constant DEFAULT_POOL_FEE = 3000;
    uint256 public constant DEFAULT_LINK_FEE = 5e17;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == MAINNET_CHAINID) {
            activeNetworkConfig = getMainnetConfig();
        } else if (block.chainid == MUMBAI_CHAINID) {
            activeNetworkConfig = getMumbaiConfig();
        } else if (block.chainid == POLYGON_CHAINID) {
            activeNetworkConfig = getPolygonConfig();
        }
    }

    function getMumbaiConfig() public view returns (NetworkConfig memory) {
        Fees memory fees = Fees({poolFee: DEFAULT_POOL_FEE, linkFee: DEFAULT_LINK_FEE});
        return NetworkConfig({
            routerAddress: 0x70499c328e1E2a3c41108bd3730F6670a44595D1,
            linkAddress: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB,
            swapRouterAddress: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
            fees: fees,
            deployerKey: vm.envUint("PRIVATE_KEY"),
            wethTokenAddress: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            usdcTokenAddress: 0x0FA8781a83E46826621b3BC094Ea2A0212e71B23
        });
    }

    function getPolygonConfig() public view returns (NetworkConfig memory) {
        Fees memory fees = Fees({poolFee: DEFAULT_POOL_FEE, linkFee: DEFAULT_LINK_FEE});
        return NetworkConfig({
            routerAddress: 0x3C3D92629A02a8D95D5CB9650fe49C3544f69B43,
            linkAddress: 0xb0897686c545045aFc77CF20eC7A532E3120E0F1,
            swapRouterAddress: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
            fees: fees,
            deployerKey: vm.envUint("ANVIL_KEY"),
            wethTokenAddress: 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619,
            usdcTokenAddress: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
        });
    }

    function getMainnetConfig() public view returns (NetworkConfig memory) {
        Fees memory fees = Fees({poolFee: DEFAULT_POOL_FEE, linkFee: DEFAULT_LINK_FEE});
        return NetworkConfig({
            routerAddress: 0xE561d5E02207fb5eB32cca20a699E0d8919a1476,
            linkAddress: 0x514910771AF9Ca656af840dff83E8264EcF986CA,
            swapRouterAddress: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
            fees: fees,
            deployerKey: vm.envUint("ANVIL_KEY"),
            wethTokenAddress: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            usdcTokenAddress: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        });
    }
}
