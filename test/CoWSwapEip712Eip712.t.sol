// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "../src/libraries/CoWSwapEip712.sol";
import "./lib/Constants.sol";

contract TestCoWSwapEip712 is Test {
    function testDomainSeparator() public {
        assertEq(
            CoWSwapEip712.domainSeparator(Constants.COWSWAP_SETTLEMENT),
            Constants.COWSWAP_TEST_DOMAIN_SEPARATOR
        );
    }

    function testConsistentMainnetDomainSeparator() public {
        // https://etherscan.io/address/0x9008d19f58aabd9ed0d60971565aa8510560ab41#readContract
        bytes32 mainnetDomainSeparator = 0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;

        vm.chainId(1);
        assertEq(
            CoWSwapEip712.domainSeparator(Constants.COWSWAP_SETTLEMENT),
            mainnetDomainSeparator
        );
    }

    function testConsistentGoerliDomainSeparator() public {
        // https://goerli.etherscan.io/address/0x9008d19f58aabd9ed0d60971565aa8510560ab41#readContract
        bytes32 goerliDomainSeparator = 0xfb378b35457022ecc5709ae5dafad9393c1387ae6d8ce24913a0c969074c07fb;

        vm.chainId(5);
        assertEq(
            CoWSwapEip712.domainSeparator(Constants.COWSWAP_SETTLEMENT),
            goerliDomainSeparator
        );
    }
}
