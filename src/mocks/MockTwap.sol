// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/ITwapOracle.sol";

contract MockTwap is ITwapOracle {
    uint256 public price;
    uint256 public lastUpdate;
    address public owner;

    error NotOwner();

    constructor(uint256 _initialPrice) {
        price = _initialPrice;
        lastUpdate = block.timestamp;
        owner = msg.sender;
    }

    function set(uint256 _price) external {
        if (msg.sender != owner) revert NotOwner();
        price = _price;
        lastUpdate = block.timestamp;
    }

    function consult() external view override returns (uint256, uint256) {
        return (price, lastUpdate);
    }
}