// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPyth.sol";

contract MezoOracleAdapter {
    IPyth public constant PYTH = IPyth(0x2880aB155794e7179c9eE2e38200202908C17B43);

    bytes32 public constant BTC_USD_ID = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;

    function getBTCPrice() external view returns (uint256) {
        (int64 price, , int32 expo, ) = PYTH.getPriceNoOlderThan(BTC_USD_ID, 60);
        return _normalize(price, expo);
    }

    function _normalize(int64 price, int32 expo) internal pure returns (uint256) {
        // Normalize to 18 decimals
        uint256 p = uint256(uint64(price));
        if (expo >= 0) {
            return p * (10 ** uint256(uint32(expo))) * 1e18 / 1e18;
        } else {
            uint256 factor = 10 ** uint256(uint32(-expo));
            return p * 1e18 / factor;
        }
    }
}