// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

library Constants {
    /// @dev CoW Swap deterministic deployer address
    address public constant COWSWAP_DEPLOYER =
        0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev Deterministic address of CoW Swap's settlement contract.
    address public constant COWSWAP_SETTLEMENT =
        0x9008D19f58AAbD9eD0D60971565AA8510560ab41;

    /// @dev Deterministic address of CoW Swap's settlement contract.
    address public constant COWSWAP_AUTHENTICATOR =
        0x2c4c28DDBdAc9C5E7055b4C863b72eA0149D8aFE;

    // Computed in the CoW Swap contract repo as:
    // > ethers.utils._TypedDataEncoder.hashDomain(domain(31337, "0x9008D19f58AAbD9eD0D60971565AA8510560ab41"))
    bytes32 public constant COWSWAP_TEST_DOMAIN_SEPARATOR =
        0x28dc932d67cd79da82085f7fbb19d7c88f84894397b07917354176f60f0096d4;
}
