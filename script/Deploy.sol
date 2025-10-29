// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

import {CoWSwapEthFlow, ICoWSwapSettlement, IWrappedNativeToken} from "src/CoWSwapEthFlow.sol";

import {ValidatedAddress} from "./ValidatedAddress.sol";
import {Obfuscator} from "./ObfuscateKey.sol";

/// @title Deployer Script for the ETH Flow Contract
/// @author CoW Swap Developers.
contract Deploy is Script {
    /// @param obfuscatedPk An obfuscated version of the private key used for
    /// deploying the contract.
    function run(bytes32 obfuscatedPk) external {
        ICoWSwapSettlement settlement = ICoWSwapSettlement(
            ValidatedAddress.cowSwapSettlement()
        );
        IWrappedNativeToken wrappedNativeToken = IWrappedNativeToken(
            ValidatedAddress.wrappedNativeToken()
        );

        uint256 pk = uint256(Obfuscator.deobfuscate(obfuscatedPk));
        Vm.Wallet memory wallet = vm.createWallet(pk);
        console.log("Deployer address:    ", wallet.addr);

        vm.broadcast(wallet.privateKey);
        CoWSwapEthFlow ethFlow = new CoWSwapEthFlow(
            settlement,
            wrappedNativeToken
        );
        console.log("Contract deployed at:", address(ethFlow));
    }
}
