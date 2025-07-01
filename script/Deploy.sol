// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "./ValidatedAddress.sol";
import "../src/CoWSwapEthFlow.sol";

/// @title Deployer Script for the ETH Flow Contract
/// @author CoW Swap Developers.
contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        try new CoWSwapEthFlow(
            ICoWSwapSettlement(ValidatedAddress.cowSwapSettlement()),
            IWrappedNativeToken(ValidatedAddress.wrappedNativeToken())
        ) {} catch {}

        vm.stopBroadcast();
    }
}
