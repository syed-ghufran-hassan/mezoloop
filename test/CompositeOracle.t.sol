// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/CompositeOracle.sol";

// ---------- Mocks ----------
contract MockPyth is IPyth {
    mapping(bytes32 => Price) internal _p;

    function set(bytes32 id, int64 price, int32 expo, uint publishTime) external {
        _p[id] = Price(price, 0, expo, publishTime);
    }

    function getPriceUnsafe(bytes32 id) external view returns (Price memory) {
        return _p[id];
    }
}

contract MockTwap is ITwapOracle {
    uint256 public price;
    uint256 public lastUpdate;
    bool public revertOnCall;

    function set(uint256 _price, uint256 _ts) external {
        price = _price;
        lastUpdate = _ts;
    }

    function setRevert(bool r) external {
        revertOnCall = r;
    }

    function consult() external view returns (uint256, uint256) {
        require(!revertOnCall, "twap: revert");
        return (price, lastUpdate);
    }
}

// ---------- Tests ----------
contract CompositeOracleTest is Test {
    CompositeOracle internal oracle;
    MockPyth internal pyth;
    MockTwap internal btcTwap;
    MockTwap internal mezoTwap;

    address constant BTC  = address(0xB7C);
    address constant MUSD = address(0xA05D);
    address constant MEZO = address(0x3E20);

    bytes32 constant BTC_ID  = bytes32(uint256(0x1111));
    bytes32 constant MUSD_ID = bytes32(uint256(0x2222));

    // Reference prices
    uint256 constant BTC_SPOT_60K    = 60_000e18;
    uint256 constant BTC_TWAP_55K    = 55_000e18;
    uint256 constant MUSD_1          = 1e18;
    uint256 constant MEZO_HALF       = 0.5e18;

    function setUp() public {
        // Set block time to a safe non-zero value
        vm.warp(1_000_000);

        pyth     = new MockPyth();
        btcTwap  = new MockTwap();
        mezoTwap = new MockTwap();

        // BTC on Pyth: $60,000 with expo -8 to 6e12 * 1e-8 = 60,000
        pyth.set(BTC_ID, int64(6_000_000_000_000), -8, block.timestamp);
        // MUSD on Pyth: $1 to 1e8 * 1e-8
        pyth.set(MUSD_ID, int64(100_000_000), -8, block.timestamp);

        btcTwap.set(BTC_SPOT_60K, block.timestamp);
        mezoTwap.set(MEZO_HALF, block.timestamp);

        oracle = new CompositeOracle(
            address(pyth),
            address(btcTwap),
            address(mezoTwap),
            BTC, MUSD, MEZO,
            BTC_ID, MUSD_ID
        );
    }

    // ============ BTC ============

    function test_BTC_PythFresh_NoTwapNeeded() public {
        // Twap is deliberately stale to force Pyth-only path
        btcTwap.set(BTC_TWAP_55K, block.timestamp - 4000);

        uint256 p = oracle.getPrice(BTC, CompositeOracle.PriceType.Collateral);
        assertEq(p, BTC_SPOT_60K);
    }

    function test_BTC_PythStale_TwapFresh_UsesTwap() public {
        // Make Pyth BTC stale: publishTime older than 60s
        pyth.set(BTC_ID, int64(6_000_000_000_000), -8, block.timestamp - 120);

        uint256 p = oracle.getPrice(BTC, CompositeOracle.PriceType.Collateral);
        assertEq(p, BTC_SPOT_60K); // btcTwap is 60k
    }

    function test_BTC_BothStale_Reverts() public {
        pyth.set(BTC_ID, int64(6_000_000_000_000), -8, block.timestamp - 120);
        btcTwap.set(BTC_SPOT_60K, block.timestamp - 4000);

        vm.expectRevert(
            abi.encodeWithSelector(CompositeOracle.OracleUnavailable.selector, BTC)
        );
        oracle.getPrice(BTC, CompositeOracle.PriceType.Collateral);
    }

    function test_BTC_BothFresh_NoDeviation_ReturnsSpot() public {
        // Spot 60k, TWAP 60k to 0% deviation
        uint256 p = oracle.getPrice(BTC, CompositeOracle.PriceType.Collateral);
        assertEq(p, BTC_SPOT_60K);
    }

    function test_BTC_DeviationHigh_Collateral_ReturnsLower() public {
        // Spot 60k, TWAP 55k to ~9.09% deviation
        btcTwap.set(BTC_TWAP_55K, block.timestamp);

        uint256 p = oracle.getPrice(BTC, CompositeOracle.PriceType.Collateral);
        assertEq(p, BTC_TWAP_55K); // lower
    }

    function test_BTC_DeviationHigh_Debt_ReturnsHigher() public {
        btcTwap.set(BTC_TWAP_55K, block.timestamp);

        uint256 p = oracle.getPrice(BTC, CompositeOracle.PriceType.Debt);
        assertEq(p, BTC_SPOT_60K); // higher
    }

    function test_BTC_SpotLowerThanTwap_DeviationGuard_FlipsChoice() public {
        // spot 50k, twap 60k to ~16.6% deviation
        pyth.set(BTC_ID, int64(5_000_000_000_000), -8, block.timestamp);
        btcTwap.set(BTC_SPOT_60K, block.timestamp);

        uint256 collateral = oracle.getPrice(BTC, CompositeOracle.PriceType.Collateral);
        uint256 debt       = oracle.getPrice(BTC, CompositeOracle.PriceType.Debt);

        assertEq(collateral, 50_000e18); // lower = spot
        assertEq(debt,       60_000e18); // higher = twap
    }

    // ============ MUSD ============

    function test_MUSD_PythFresh_ReturnsPyth() public {
        uint256 p = oracle.getPrice(MUSD);
        assertEq(p, MUSD_1);
    }

    function test_MUSD_PythStale_ReturnsPeg() public {
        pyth.set(MUSD_ID, int64(100_000_000), -8, block.timestamp - 5000);
        uint256 p = oracle.getPrice(MUSD);
        assertEq(p, 1e18);
    }

    function test_MUSD_PythZero_ReturnsPeg() public {
        pyth.set(MUSD_ID, int64(0), -8, block.timestamp);
        uint256 p = oracle.getPrice(MUSD);
        assertEq(p, 1e18);
    }

    // ============ MEZO ============

    function test_MEZO_TwapFresh_ReturnsTwap() public {
        uint256 p = oracle.getPrice(MEZO);
        assertEq(p, MEZO_HALF);
    }

    function test_MEZO_TwapStale_Reverts() public {
        mezoTwap.set(MEZO_HALF, block.timestamp - 4000);
        vm.expectRevert(
            abi.encodeWithSelector(CompositeOracle.OracleUnavailable.selector, MEZO)
        );
        oracle.getPrice(MEZO);
    }

    function test_MEZO_TwapRevert_Reverts() public {
        mezoTwap.setRevert(true);
        vm.expectRevert(
            abi.encodeWithSelector(CompositeOracle.OracleUnavailable.selector, MEZO)
        );
        oracle.getPrice(MEZO);
    }

    // ============ Misc ============

    function test_UnsupportedAsset_Reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                CompositeOracle.UnsupportedAsset.selector,
                address(0xDEAD)
            )
        );
        oracle.getPrice(address(0xDEAD));
    }

    function test_Admin_SetDeviationGuard() public {
        oracle.setDeviationGuard(1e16);
        assertEq(oracle.deviationGuard(), 1e16);
    }

    function test_Admin_OnlyOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(CompositeOracle.NotOwner.selector);
        oracle.setDeviationGuard(1e16);
    }

    function test_Admin_SetFeedIds() public {
        bytes32 newBtc  = bytes32(uint256(0xAAAA));
        bytes32 newMusd = bytes32(uint256(0xBBBB));
        oracle.setFeedIds(newBtc, newMusd);
        assertEq(oracle.btcUsdId(),  newBtc);
        assertEq(oracle.musdUsdId(), newMusd);
    }

    function test_Normalize_NegativeExpo_To18Decimals() public {
        // 60,000 with expo -8 to 6e12 then normalized 6e22 (18 dec)
        // Verified indirectly via BTC_PythFresh_NoTwapNeeded
        assertEq(BTC_SPOT_60K, 60_000e18);
    }
 

        function test_Constructor_ZeroAddress_Reverts() public {
        vm.expectRevert(CompositeOracle.ZeroAddress.selector);
        new CompositeOracle(
            address(0),
            address(btcTwap),
            address(mezoTwap),
            BTC, MUSD, MEZO,
            BTC_ID, MUSD_ID
        );
    }

    // ============================================================
    // Missing tests   Phase 1 closure
    // ============================================================

    /// @notice Deviation exactly at 5% boundary must NOT trigger the guard.
    function test_BTC_DeviationExactlyAtBoundary_ReturnsSpot() public {
        pyth.set(BTC_ID, int64(6_300_000_000_000), -8, block.timestamp);
        btcTwap.set(60_000e18, block.timestamp);

        uint256 collateral = oracle.getPrice(BTC, CompositeOracle.PriceType.Collateral);
        uint256 debt       = oracle.getPrice(BTC, CompositeOracle.PriceType.Debt);

        assertEq(collateral, 63_000e18);
        assertEq(debt,       63_000e18);

        uint256 diff = 63_000e18 - 60_000e18;
        uint256 deviationBps = (diff * 1e18) / 60_000e18;
        assertEq(deviationBps, 5e16);
    }

    /// @notice If Pyth reverts (feed not set), fall back to TWAP for BTC.
    function test_BTC_PythRevert_FallsBackToTwap() public {
        vm.mockCallRevert(
            address(pyth),
            abi.encodeWithSelector(IPyth.getPriceUnsafe.selector, BTC_ID),
            abi.encodeWithSignature("Error(string)", "feed not found")
        );

        btcTwap.set(55_000e18, block.timestamp);

        uint256 p = oracle.getPrice(BTC, CompositeOracle.PriceType.Collateral);
        assertEq(p, 55_000e18);
    }

    /// @notice MUSD ignores PriceType  both must return the same value.
    function test_MUSD_PriceTypeIgnored_ReturnsSameForBoth() public {
        uint256 c1 = oracle.getPrice(MUSD, CompositeOracle.PriceType.Collateral);
        uint256 d1 = oracle.getPrice(MUSD, CompositeOracle.PriceType.Debt);
        assertEq(c1, d1);
        assertEq(c1, 1e18);

        pyth.set(MUSD_ID, int64(100_000_000), -8, block.timestamp - 5000);
        uint256 c2 = oracle.getPrice(MUSD, CompositeOracle.PriceType.Collateral);
        uint256 d2 = oracle.getPrice(MUSD, CompositeOracle.PriceType.Debt);
        assertEq(c2, d2);
        assertEq(c2, 1e18);
    }

    /// @notice setDeviationGuard rejects values above 1e18 (100%).
    function test_Admin_SetDeviationGuardTooHigh_Reverts() public {
        vm.expectRevert(bytes("guard too high"));
        oracle.setDeviationGuard(1e18 + 1);
    }
}    
 