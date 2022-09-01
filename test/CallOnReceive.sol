// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

// Used to test reentrancy when receiving ETH
contract CallOnReceive {
    address payable public to;
    uint256 public value;
    bytes public data;

    // Store call result for later retrieval
    bool public lastFallbackCallSuccess;
    bytes public lastFallbackCallReturnData;

    receive() external payable {
        // solhint-disable-next-line avoid-low-level-calls
        (lastFallbackCallSuccess, lastFallbackCallReturnData) = to.call{
            value: value
        }(data);
    }

    function execCall(
        address payable _to,
        uint256 _value,
        bytes memory _data
    ) public returns (bytes memory) {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory result) = _to.call{value: _value}(_data);
        if (success == false) {
            // Forward revert error
            // solhint-disable-next-line no-inline-assembly
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }
        return result;
    }

    function setCallOnReceive(
        address payable _to,
        uint256 _value,
        bytes calldata _data
    ) external {
        to = _to;
        value = _value;
        data = _data;
    }
}
