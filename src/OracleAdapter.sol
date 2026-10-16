// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract OracleAdapter {
    // Hardcoded for first testnet deployment
    function getPrice(address asset) external pure returns (uint256) {
        // Return 1 USD in 18 decimals
        // Replace with real logic later
        asset; // silence warning
        return 1e18;
    }
}