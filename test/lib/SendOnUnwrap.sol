// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

// solhint-disable avoid-low-level-calls

// Used to test ETH unwrapping without deploying WETH
// Note: importing "forge-std/Test" and minting tokens causes a panic in the test.
contract SendOnUnwrap {
    function withdraw(uint256 amount) external {
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Sending ETH failed");
    }
}
