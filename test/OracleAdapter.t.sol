// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/OracleAdapter.sol";

contract OracleAdapterTest is Test {
    OracleAdapter oracle;

    function setUp() public {
        oracle = new OracleAdapter();
    }

    function testGetPrice() public {
        uint256 price = oracle.getPrice(address(0x1));
        assertEq(price, 1e18);
    }
}