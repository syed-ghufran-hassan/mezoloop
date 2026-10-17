// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUniswapV2Pair {
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
}

contract TwapOracleAdapter {
    IUniswapV2Pair public immutable pool;
    uint256 public immutable token0Decimals;
    uint256 public immutable token1Decimals;

    struct Observation {
        uint256 price0Cumulative;
        uint256 price1Cumulative;
        uint32 timestamp;
    }

    Observation public lastObservation;

    constructor(address _pool, uint256 _token0Decimals, uint256 _token1Decimals) {
        pool = IUniswapV2Pair(_pool);
        token0Decimals = _token0Decimals;
        token1Decimals = _token1Decimals;
    }

    /// @notice Update the cumulative price snapshot. Callable by anyone.
    function update() external {
        lastObservation = Observation({
            price0Cumulative: pool.price0CumulativeLast(),
            price1Cumulative: pool.price1CumulativeLast(),
            timestamp: uint32(block.timestamp)
        });
    }

    /// @notice Consult the TWAP over a given window in seconds.
    /// @return twapPrice0 Price of token0 in terms of token1, 18 decimals.
    function consult(uint32 window) external view returns (uint256) {
        require(lastObservation.timestamp > 0, "No observation");
        require(block.timestamp - lastObservation.timestamp >= window, "Window too short");

        uint256 price0Cum = pool.price0CumulativeLast();
        uint256 price1Cum = pool.price1CumulativeLast();

        uint256 delta0 = price0Cum - lastObservation.price0Cumulative;
        uint256 delta1 = price1Cum - lastObservation.price1Cumulative;
        uint256 elapsed = block.timestamp - lastObservation.timestamp;

        // price of token0 in token1
        uint256 price0InToken1 = delta0 / elapsed;
        // Normalize to 18 decimals
        return price0InToken1 * (10 ** token1Decimals) / (10 ** token0Decimals) * 1e18 / 1e18;
    }
}