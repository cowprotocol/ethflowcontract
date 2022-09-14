// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

library FillWithSameByte {
    function toAddress(uint8 b) public pure returns (address) {
        return address(uint160(repeatByte(b, 20)));
    }

    function toBytes32(uint8 b) public pure returns (bytes32) {
        return bytes32(repeatByte(b, 32));
    }

    function toUint32(uint8 b) public pure returns (uint32) {
        return uint32(repeatByte(b, 4));
    }

    function toUint128(uint8 b) public pure returns (uint128) {
        return uint128(repeatByte(b, 16));
    }

    function toUint256(uint8 b) public pure returns (uint256) {
        return repeatByte(b, 32);
    }

    function toVector(uint8 b, uint256 times)
        public
        pure
        returns (bytes memory result)
    {
        result = new bytes(times);
        for (uint256 i = 0; i < times; i++) {
            result[i] = bytes1(b);
        }
    }

    function repeatByte(uint8 b, uint8 times) internal pure returns (uint256) {
        uint256 n = 0;
        for (uint8 i = 0; i < times; i++) {
            n = (n << 8) + b;
        }
        return n;
    }
}
