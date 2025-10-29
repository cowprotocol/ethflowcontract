// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

library Obfuscator {
    bytes32 internal constant SHIFT =
        0x31337def1beef31337def1beef31337def1beef31337def1beef1173def1beef;

    function obfuscate(bytes32 input) internal pure returns (bytes32) {
        return SHIFT ^ input;
    }

    function deobfuscate(bytes32 input) internal pure returns (bytes32) {
        // This function is the inverse of itself.
        return obfuscate(input);
    }
}

/// @title Helper script to obfuscate a key for use in the deployment process.
/// @dev This obfuscation isn't intended to be secure, it's just here to avoid
/// reusing the private keys in other contexts by accident.
/// @author CoW Swap Developers.
contract ObfuscateKey is Script {
    function run(bytes32 key) external pure {
        console.log("Obfuscation parameter:", vm.toString(Obfuscator.SHIFT));
        console.log(
            "Obfuscated key:       ",
            vm.toString(Obfuscator.obfuscate(key))
        );
    }
}
