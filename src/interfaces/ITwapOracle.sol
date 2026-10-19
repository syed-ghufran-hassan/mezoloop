// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITwapOracle {
    /// @return price Price in 18 decimals
    /// @return lastUpdate Timestamp of last TWAP observation
    function consult() external view returns (uint256 price, uint256 lastUpdate);
}