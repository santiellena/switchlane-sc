// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address routerAddress;
        address linkAddress;
        address swapRouterAddress;
        uint256 deployerKey;
    }

    uint256 public constant MUMBAI_CHAINID = 80001;
    uint256 public constant POLYGON_CHAINID = 137;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == MUMBAI_CHAINID) {
            activeNetworkConfig = getMumbaiConfig();
        } else if (block.chainid == POLYGON_CHAINID) {
            activeNetworkConfig = getPolygonConfig();
        }
    }

    function getMumbaiConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            routerAddress: 0x70499c328e1E2a3c41108bd3730F6670a44595D1,
            linkAddress: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB,
            swapRouterAddress: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getPolygonConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            routerAddress: 0x3C3D92629A02a8D95D5CB9650fe49C3544f69B43,
            linkAddress: 0xb0897686c545045aFc77CF20eC7A532E3120E0F1,
            swapRouterAddress: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
            deployerKey: vm.envUint("ANVIL_KEY")
        });
    }
}
