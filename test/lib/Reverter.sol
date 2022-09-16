// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

// It's not possible to mock reverting a function.
// https://github.com/foundry-rs/foundry/issues/2740
// This contract is a workaround to trigger a revert.
contract Reverter {
    receive() external payable {
        revert("Mock revert");
    }
}
