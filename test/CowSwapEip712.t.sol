// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "../src/libraries/CowSwapEip712.sol";

import "forge-std/console.sol";

contract TestCowSwapEip712 is Test {
    function setUp() public {}

    function testDomainSeparator() public {
        // Computed in the CowSwap contract repo as:
        // > ethers.utils._TypedDataEncoder.hashDomain(domain(31337, "0x9008D19f58AAbD9eD0D60971565AA8510560ab41"))
        bytes32 ANVIL_DOMAIN_SEPARATOR = 0x28dc932d67cd79da82085f7fbb19d7c88f84894397b07917354176f60f0096d4;

        assertEq(CowSwapEip712.domainSeparator(), ANVIL_DOMAIN_SEPARATOR);
    }

    function testConsistentMainnetDomainSeparator() public {
        // https://etherscan.io/address/0x9008d19f58aabd9ed0d60971565aa8510560ab41#readContract
        bytes32 MAINNET_DOMAIN_SEPARATOR = 0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;

        vm.chainId(1);
        assertEq(CowSwapEip712.domainSeparator(), MAINNET_DOMAIN_SEPARATOR);
    }

    function testConsistentGoerliDomainSeparator() public {
        // https://goerli.etherscan.io/address/0x9008d19f58aabd9ed0d60971565aa8510560ab41#readContract
        bytes32 GOERLI_DOMAIN_SEPARATOR = 0xfb378b35457022ecc5709ae5dafad9393c1387ae6d8ce24913a0c969074c07fb;
        
        vm.chainId(5);
        assertEq(CowSwapEip712.domainSeparator(), GOERLI_DOMAIN_SEPARATOR);
    }
}
