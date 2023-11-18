// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

// solhint-disable reason-string

import "../src/interfaces/ICoWSwapSettlement.sol";
import "../src/libraries/CoWSwapEip712.sol";
import "../src/vendored/IERC20.sol";

/// @title Constant Address Validator
/// @author CoW Swap Developers.
library ValidatedAddress {
    uint256 internal constant CHAINID_MAINNET = 1;
    uint256 internal constant CHAINID_RINKEBY = 4;
    uint256 internal constant CHAINID_GOERLI = 5;
    uint256 internal constant CHAINID_GNOSISCHAIN = 100;
    uint256 internal constant CHAINID_SEPOLIA = 11155111;

    function cowSwapSettlement()
        internal
        view
        returns (ICoWSwapSettlement settlement)
    {
        require(
            (chainId() == CHAINID_MAINNET) ||
                (chainId() == CHAINID_RINKEBY) ||
                (chainId() == CHAINID_GOERLI) ||
                (chainId() == CHAINID_GNOSISCHAIN) ||
                (chainId() == CHAINID_SEPOLIA),
            "Settlement contract not available on this chain"
        );
        settlement = ICoWSwapSettlement(
            0x9008D19f58AAbD9eD0D60971565AA8510560ab41
        );
        require(
            CoWSwapEip712.domainSeparator(address(settlement)) ==
                WithDomainSeparator(address(settlement)).domainSeparator(),
            "Bad domain separator for settlement contract"
        );
    }

    function wrappedNativeToken()
        internal
        view
        returns (address _wrappedNativeToken)
    {
        if (chainId() == CHAINID_MAINNET) {
            _wrappedNativeToken = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            require(eq(WithSymbol(_wrappedNativeToken).symbol(), "WETH"));
        } else if (chainId() == CHAINID_RINKEBY) {
            _wrappedNativeToken = 0xc778417E063141139Fce010982780140Aa0cD5Ab;
            require(eq(WithSymbol(_wrappedNativeToken).symbol(), "WETH"));
        } else if (chainId() == CHAINID_GOERLI) {
            _wrappedNativeToken = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
            require(eq(WithSymbol(_wrappedNativeToken).symbol(), "WETH"));
        } else if (chainId() == CHAINID_GNOSISCHAIN) {
            _wrappedNativeToken = 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d;
            require(eq(WithSymbol(_wrappedNativeToken).symbol(), "WXDAI"));
        } else if (chainId() == CHAINID_SEPOLIA) {
            _wrappedNativeToken = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
            require(eq(WithSymbol(_wrappedNativeToken).symbol(), "WETH"));
        } else {
            revert("Wrapped native token not supported on this chain");
        }
    }

    function chainId() private view returns (uint256 _chainId) {
        // NOTE: Currently, the only way to get the chain ID in solidity is
        // using assembly.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            _chainId := chainid()
        }
    }

    function eq(string memory lhs, string memory rhs)
        private
        pure
        returns (bool)
    {
        return keccak256(abi.encode(lhs)) == keccak256(abi.encode(rhs));
    }
}

interface WithSymbol {
    function symbol() external view returns (string memory);
}

interface WithDomainSeparator {
    function domainSeparator() external view returns (bytes32);
}
