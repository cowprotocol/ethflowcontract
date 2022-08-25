// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

/// @title CoW Swap Settlement Contract Interface
/// @author CoW Swap Developers
/// @dev This interface collects the functions of the CoW Swap settlement contract that are used by the ETH flow
/// contract.
interface ICoWSwapSettlement {
    /// @dev Map each user order by UID to the amount that has been filled so
    /// far. If this amount is larger than or equal to the amount traded in the
    /// order (amount sold for sell orders, amount bought for buy orders) then
    /// the order cannot be traded anymore. If the order is fill or kill, then
    /// this value is only used to determine whether the order has already been
    /// executed.
    function filledAmount(bytes memory orderUid) external returns (uint256);
}
