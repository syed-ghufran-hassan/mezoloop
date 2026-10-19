// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title CompositeOracle
/// @notice USD price oracle for BTC, MUSD, and MEZO on Mezo.
///         Primary: Pyth (BTC, MUSD). Fallback: TWAP or stablecoin peg.
///         MEZO: always TWAP-derived. Deviation guard returns conservative price.
/// @dev All returned prices use 18 decimals.

import "./interfaces/IPyth.sol";
import "./interfaces/ITwapOracle.sol";

contract CompositeOracle {
    // ---------- Types ----------
    enum PriceType {
        Collateral, // conservative   lower
        Debt        // conservative   higher
    }

    // ---------- Errors ----------
    error ZeroAddress();
    error UnsupportedAsset(address asset);
    error OracleUnavailable(address asset);
    error InvalidPythPrice();
    error NotOwner();

    // ---------- Events ----------
    event FeedIdsUpdated(bytes32 btcUsdId, bytes32 musdUsdId);
    event StalenessUpdated(uint256 pyth, uint256 twap);
    event DeviationGuardUpdated(uint256 newGuard);
    event DeviationGuardTriggered(
        address indexed asset,
        uint256 spot,
        uint256 twap,
        uint256 deviationBps,
        uint256 chosen
    );
    event OwnerUpdated(address newOwner);

    // ---------- Immutables ----------
    IPyth public immutable pyth;
    ITwapOracle public immutable btcTwap;  // returns BTC/USD
    ITwapOracle public immutable mezoTwap; // returns MEZO/USD

    // ---------- Config ----------
    bytes32 public btcUsdId;
    bytes32 public musdUsdId;

    address public immutable btc;
    address public immutable musd;
    address public immutable mezo;

    uint256 public pythMaxStaleness = 60;      // 60s
    uint256 public twapMaxStaleness = 1800;    // 30 min
    uint256 public deviationGuard = 5e16;      // 5%
    uint256 public constant MUSD_PEG = 1e18;   // $1.00

    address public owner;

    // ---------- Modifiers ----------
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ---------- Constructor ----------
    constructor(
        address _pyth,
        address _btcTwap,
        address _mezoTwap,
        address _btc,
        address _musd,
        address _mezo,
        bytes32 _btcUsdId,
        bytes32 _musdUsdId
    ) {
        if (
            _pyth == address(0) || _btc == address(0) ||
            _musd == address(0) || _mezo == address(0)
        ) revert ZeroAddress();

        pyth = IPyth(_pyth);
        btcTwap = ITwapOracle(_btcTwap);
        mezoTwap = ITwapOracle(_mezoTwap);
        btc = _btc;
        musd = _musd;
        mezo = _mezo;
        btcUsdId = _btcUsdId;
        musdUsdId = _musdUsdId;
        owner = msg.sender;
    }

    // ---------- Admin ----------
    function setFeedIds(bytes32 _btcUsdId, bytes32 _musdUsdId) external onlyOwner {
        btcUsdId = _btcUsdId;
        musdUsdId = _musdUsdId;
        emit FeedIdsUpdated(_btcUsdId, _musdUsdId);
    }

    function setStaleness(uint256 _pyth, uint256 _twap) external onlyOwner {
        pythMaxStaleness = _pyth;
        twapMaxStaleness = _twap;
        emit StalenessUpdated(_pyth, _twap);
    }

        function setDeviationGuard(uint256 newGuard) external onlyOwner {
        require(newGuard <= 1e18, "guard too high");
        deviationGuard = newGuard;
        emit DeviationGuardUpdated(newGuard);
    }

    function transferOwnership(address _owner) external onlyOwner {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
        emit OwnerUpdated(_owner);
    }

    // ---------- Public API ----------
    /// @notice Returns USD price of `asset` with 18 decimals.
    /// @param asset BTC, MUSD, or MEZO address
    /// @param priceType Collateral (conservative low) or Debt (conservative high)
    function getPrice(address asset, PriceType priceType)
        external
        view
        returns (uint256)
    {
        if (asset == btc)  return _btcPrice(priceType);
        if (asset == musd) return _musdPrice();
        if (asset == mezo) return _mezoPrice();
        revert UnsupportedAsset(asset);
    }

    /// @notice Convenience default (Collateral) price lookup.
    function getPrice(address asset) external view returns (uint256) {
        if (asset == btc)  return _btcPrice(PriceType.Collateral);
        if (asset == musd) return _musdPrice();
        if (asset == mezo) return _mezoPrice();
        revert UnsupportedAsset(asset);
    }

    // ---------- BTC ----------
    function _btcPrice(PriceType priceType) internal view returns (uint256) {
        (uint256 spot, bool spotOk) = _tryPyth(btcUsdId);
        (uint256 twap, bool twapOk) = _tryTwap(btcTwap);

        if (spotOk && twapOk) {
            return _guard(btc, spot, twap, priceType);
        }
        if (spotOk) return spot;
        if (twapOk) return twap;
        revert OracleUnavailable(btc);
    }

    // ---------- MUSD ----------
    function _musdPrice() internal view returns (uint256) {
        (uint256 spot, bool spotOk) = _tryPyth(musdUsdId);
        if (spotOk) return spot;
        // Stablecoin fallback — only reached when Pyth is stale/unavailable.
        // Documented risk: real depeg events aren't caught by this fallback.
        return MUSD_PEG;
    }

    // ---------- MEZO ----------
    function _mezoPrice() internal view returns (uint256) {
        (uint256 twap, bool twapOk) = _tryTwap(mezoTwap);
        if (!twapOk) revert OracleUnavailable(mezo);
        return twap;
    }

    // ---------- Helpers ----------
    function _tryPyth(bytes32 feedId)
        internal
        view
        returns (uint256 price, bool ok)
    {
        if (feedId == bytes32(0)) return (0, false);
        try pyth.getPriceUnsafe(feedId) returns (IPyth.Price memory p) {
            if (p.price <= 0) return (0, false);
            if (p.publishTime == 0) return (0, false);
            if (block.timestamp - p.publishTime > pythMaxStaleness) return (0, false);
            return (_normalize(p.price, p.expo), true);
        } catch {
            return (0, false);
        }
    }

    function _tryTwap(ITwapOracle twap)
        internal
        view
        returns (uint256 price, bool ok)
    {
        if (address(twap) == address(0)) return (0, false);
        try twap.consult() returns (uint256 p, uint256 ts) {
            if (p == 0 || ts == 0) return (0, false);
            if (block.timestamp - ts > twapMaxStaleness) return (0, false);
            return (p, true);
        } catch {
            return (0, false);
        }
    }

    function _guard(
        address asset,
        uint256 spot,
        uint256 twap,
        PriceType priceType
    ) internal view returns (uint256 chosen) {
        uint256 diff = spot > twap ? spot - twap : twap - spot;
        uint256 deviationBps = (diff * 1e18) / twap;

        if (deviationBps > deviationGuard) {
            if (priceType == PriceType.Collateral) {
                chosen = spot < twap ? spot : twap; // lower
            } else {
                chosen = spot > twap ? spot : twap; // higher
            }
            return chosen;
        }
        return spot; // within tolerance   prefer fresher spot
    }

    function _normalize(int64 price, int32 expo) internal pure returns (uint256) {
        if (price <= 0) revert InvalidPythPrice();
        uint256 p = uint256(uint64(price));

        if (expo >= 0) {
            return p * (10 ** uint256(uint32(expo))) * 1e18 / 1e18;
        }
        uint256 absExpo = uint32(-expo);
        if (absExpo >= 18) {
            return p / (10 ** (absExpo - 18));
        }
        return p * (10 ** (18 - absExpo));
    }
}