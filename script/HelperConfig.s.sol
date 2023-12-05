// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC20Mock} from "../test/mock/ERC20Mock.sol";

contract HelperConfig is Script {
    struct Fees {
        uint256 linkMarginFee;
        uint24 poolFee;
        address linkPriceFeedAddress;
    }

    struct NetworkConfig {
        address routerAddress;
        address linkAddress;
        address swapRouterAddress;
        Fees fees;
        uint256 deployerKey;
        address fromTokenAddress;
        address toTokenAddress;
        bool test;
    }

    uint256 public constant SEPOLIA_CHAINID = 11155111;
    uint256 public constant MUMBAI_CHAINID = 80001;
    uint256 public constant POLYGON_CHAINID = 137;
    uint256 public constant MAINNET_CHAINID = 1;

    uint24 public constant DEFAULT_POOL_FEE = 3000;
    uint256 public constant DEFAULT_LINK_FEE = 1e17;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == MAINNET_CHAINID) {
            activeNetworkConfig = getMainnetConfig();
        } else if (block.chainid == MUMBAI_CHAINID) {
            activeNetworkConfig = getMumbaiConfig();
        } else if (block.chainid == POLYGON_CHAINID) {
            activeNetworkConfig = getPolygonConfig();
        } else if (block.chainid == SEPOLIA_CHAINID) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getMumbaiConfig() public view returns (NetworkConfig memory) {
        Fees memory fees = Fees({
            poolFee: DEFAULT_POOL_FEE,
            linkMarginFee: DEFAULT_LINK_FEE,
            linkPriceFeedAddress: 0x1C2252aeeD50e0c9B64bDfF2735Ee3C932F5C408
        });
        return NetworkConfig({
            routerAddress: 0x70499c328e1E2a3c41108bd3730F6670a44595D1,
            linkAddress: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB,
            swapRouterAddress: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
            fees: fees,
            deployerKey: vm.envUint("ANVIL_KEY"),
            fromTokenAddress: 0x02C5549fC884Ef24553202AbEdB9876eCfB171aD, // SLN test token
            toTokenAddress: 0xf1E3A5842EeEF51F2967b3F05D45DD4f4205FF40, // CCIP-BnM
            test: true
        });
    }

    function getPolygonConfig() public view returns (NetworkConfig memory) {
        Fees memory fees = Fees({
            poolFee: DEFAULT_POOL_FEE,
            linkMarginFee: DEFAULT_LINK_FEE,
            linkPriceFeedAddress: 0xd9FFdb71EbE7496cC440152d43986Aae0AB76665
        });
        return NetworkConfig({
            routerAddress: 0x3C3D92629A02a8D95D5CB9650fe49C3544f69B43,
            linkAddress: 0xb0897686c545045aFc77CF20eC7A532E3120E0F1,
            swapRouterAddress: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
            fees: fees,
            deployerKey: vm.envUint("ANVIL_KEY"),
            fromTokenAddress: 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619,
            toTokenAddress: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359,
            test: true
        });
    }

    function getMainnetConfig() public view returns (NetworkConfig memory) {
        Fees memory fees = Fees({
            poolFee: DEFAULT_POOL_FEE,
            linkMarginFee: DEFAULT_LINK_FEE,
            linkPriceFeedAddress: 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c
        });
        return NetworkConfig({
            routerAddress: 0xE561d5E02207fb5eB32cca20a699E0d8919a1476,
            linkAddress: 0x514910771AF9Ca656af840dff83E8264EcF986CA,
            swapRouterAddress: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
            fees: fees,
            deployerKey: vm.envUint("ANVIL_KEY"),
            fromTokenAddress: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            toTokenAddress: 0x514910771AF9Ca656af840dff83E8264EcF986CA, // LINK
            test: true
        });
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        Fees memory fees = Fees({
            poolFee: DEFAULT_POOL_FEE,
            linkMarginFee: DEFAULT_LINK_FEE,
            linkPriceFeedAddress: 0xc59E3633BAAC79493d908e63626716e204A45EdF
        });
        return NetworkConfig({
            routerAddress: 0xD0daae2231E9CB96b94C8512223533293C3693Bf,
            linkAddress: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            swapRouterAddress: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
            fees: fees,
            deployerKey: vm.envUint("ANVIL_KEY"),
            fromTokenAddress: 0x097D90c9d3E0B50Ca60e1ae45F6A81010f9FB534,
            toTokenAddress: 0x779877A7B0D9E8603169DdbD7836e478b4624789, // LINK
            test: true
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.routerAddress != address(0)) {
            return activeNetworkConfig;
        }

        uint256 deployer = vm.envUint("ANVIL_KEY");

        vm.startBroadcast(deployer);

        ERC20Mock weth = new ERC20Mock("Wrapped ETH", "WETH");
        ERC20Mock usdc = new ERC20Mock("Circle USD", "USDC");

        vm.stopBroadcast();

        Fees memory fees =
            Fees({poolFee: DEFAULT_POOL_FEE, linkMarginFee: DEFAULT_LINK_FEE, linkPriceFeedAddress: address(1)});

        return NetworkConfig({
            routerAddress: address(2),
            linkAddress: address(3),
            swapRouterAddress: address(4),
            fees: fees,
            deployerKey: deployer,
            fromTokenAddress: address(weth),
            toTokenAddress: address(usdc),
            test: true
        });
    }
}
