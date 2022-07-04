// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

/// Code mostly copied from:
/// <https://raw.githubusercontent.com/cowprotocol/contracts/v1.0.0/src/contracts/mixins/GPv2Signing.sol>

import "forge-std/console.sol";

library CowSwapEip712 {
    /// @dev Deterministic address of CowSwap's settlement contract.
    address constant COWSWAP_ADDRESS =
        0x9008D19f58AAbD9eD0D60971565AA8510560ab41;

    /// @dev The EIP-712 domain type hash used for computing the domain
    /// separator.
    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    /// @dev The EIP-712 domain name used for computing the domain separator.
    bytes32 private constant DOMAIN_NAME = keccak256("Gnosis Protocol");

    /// @dev The EIP-712 domain version used for computing the domain separator.
    bytes32 private constant DOMAIN_VERSION = keccak256("v2");

    function domainSeparator() internal view returns (bytes32) {
        // NOTE: Currently, the only way to get the chain ID in solidity is
        // using assembly.
        uint256 chainId;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainId := chainid()
        }
        console.log(chainId);

        return
            keccak256(
                abi.encode(
                    DOMAIN_TYPE_HASH,
                    DOMAIN_NAME,
                    DOMAIN_VERSION,
                    chainId,
                    COWSWAP_ADDRESS
                )
            );
    }
}
