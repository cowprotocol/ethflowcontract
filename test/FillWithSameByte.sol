// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

library FillWithSameByte {
    function toAddress(uint8 b) public pure returns (address) {
        return address(uint160(repeatByte(b, 20)));
    }

    function toBytes32(uint8 b) public pure returns (bytes32) {
        return bytes32(repeatByte(b, 32));
    }

    function toInt64(uint8 b) public pure returns (int64) {
        return int64(int256(repeatByte(b, 8)));
    }

    function toUint32(uint8 b) public pure returns (uint32) {
        return uint32(repeatByte(b, 4));
    }

    function toUint256(uint8 b) public pure returns (uint256) {
        return repeatByte(b, 32);
    }

    function repeatByte(uint8 b, uint8 times) internal pure returns (uint256) {
        uint256 n = 0;
        for (uint8 i = 0; i < times; i++) {
            n = (n << 8) + b;
        }
        return n;
    }
}
