// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPyth {
    function getPriceNoOlderThan(bytes32 id, uint age)
        external
        view
        returns (int64 price, uint64 conf, int32 expo, uint publishTime);
}