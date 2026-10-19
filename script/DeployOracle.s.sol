// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/CompositeOracle.sol";
import "../src/mocks/MockTwap.sol";

contract DeployOracle is Script {
    // ----- Mezo Testnet (Chain ID 31611) -----
    address constant PYTH            = 0x2880aB155794e7179c9eE2e38200202908C17B43;
    bytes32 constant BTC_USD_ID      = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;
    address constant MUSD            = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503;

    // Placeholders — no real ERC20 for these on testnet
    address constant BTC_PLACEHOLDER  = address(0xB7C);
    address constant MEZO_PLACEHOLDER = address(0x3E20);

    // No MUSD/USD Pyth feed on testnet → zero triggers $1 peg fallback
    bytes32 constant MUSD_USD_ID = bytes32(0);

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // BTC TWAP placeholder — $60,000 (BTC is native, no ERC20 pool to read)
        MockTwap btcTwap = new MockTwap(60_000e18);

        // MEZO TWAP placeholder — $0.50
        // Wave 2: replace with TwapOracleAdapter on Mezo Mainnet pool
        //         0x1d6e8d24c133535f2d00676f66a0e824f84765ff
        MockTwap mezoTwap = new MockTwap(0.5e18);

        // Composite oracle
        CompositeOracle oracle = new CompositeOracle(
            PYTH,
            address(btcTwap),
            address(mezoTwap),
            BTC_PLACEHOLDER,
            MUSD,
            MEZO_PLACEHOLDER,
            BTC_USD_ID,
            MUSD_USD_ID
        );

        vm.stopBroadcast();

        console.log("Deployer:          ", deployer);
        console.log("MockTwap (BTC):    ", address(btcTwap));
        console.log("MockTwap (MEZO):   ", address(mezoTwap));
        console.log("CompositeOracle:   ", address(oracle));
    }
}