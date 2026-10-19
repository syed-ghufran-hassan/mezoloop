// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint publishTime;
    }

    function getPriceUnsafe(bytes32 id) external view returns (Price memory);
}