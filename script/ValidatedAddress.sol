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
    uint256 internal constant CHAINID_ARBITRUM = 42161;
    uint256 internal constant CHAINID_BASE = 8453;
    uint256 internal constant CHAINID_POLYGON = 137;
    uint256 internal constant CHAINID_BSC = 56;
    uint256 internal constant CHAINID_AVALANCHE = 43114;
    uint256 internal constant CHAINID_OPTIMISM = 10;

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
                (chainId() == CHAINID_ARBITRUM) ||
                (chainId() == CHAINID_BASE) ||
                (chainId() == CHAINID_POLYGON) ||
                (chainId() == CHAINID_BSC) ||
                (chainId() == CHAINID_AVALANCHE) ||
                (chainId() == CHAINID_OPTIMISM) ||
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
        } else if (chainId() == CHAINID_ARBITRUM) {
            _wrappedNativeToken = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
            require(eq(WithSymbol(_wrappedNativeToken).symbol(), "WETH"));
        } else if (chainId() == CHAINID_BASE) {
            _wrappedNativeToken = 0x4200000000000000000000000000000000000006;
            require(eq(WithSymbol(_wrappedNativeToken).symbol(), "WETH"));
        } else if (chainId() == CHAINID_POLYGON) {
            _wrappedNativeToken = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
            require(eq(WithSymbol(_wrappedNativeToken).symbol(), "POL"));
        } else if (chainId() == CHAINID_BSC) {
            _wrappedNativeToken = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
            require(eq(WithSymbol(_wrappedNativeToken).symbol(), "BNB"));
        } else if (chainId() == CHAINID_AVALANCHE) {
            _wrappedNativeToken = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
            require(eq(WithSymbol(_wrappedNativeToken).symbol(), "AVAX"));
        } else if (chainId() == CHAINID_OPTIMISM) {
            _wrappedNativeToken = 0x4200000000000000000000000000000000000006;
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
