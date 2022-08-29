// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "../libraries/EthFlowOrder.sol";

/// @title CoW Swap ETH Flow Interface
/// @author CoW Swap Developers
interface ICoWSwapEthFlow {
    /// @dev Error thrown when trying to create a new order whose order hash is the same as an order hash that was
    /// already assigned.
    error OrderIsAlreadyOwned(bytes32 orderHash);

    /// @dev Error thrown when trying to create an order without sending the expected amount of ETH to this contract.
    error IncorrectEthAmount();

    /// @dev Error thrown if trying to delete an order while not allowed.
    error NotAllowedToDeleteOrder(bytes32 orderHash);

    /// @dev Error thrown when unsuccessfully sending ETH to an address.
    error EthTransferFailed();

    /// @dev Function that creates and broadcasts an ETH flow order that sells native ETH. The order is paid for when
    /// the caller sends out the transaction. The caller takes ownership of the new order.
    ///
    /// @param order The data describing the order to be created. See [`EthFlowOrder.Data`] for extra information on
    /// each parameter.
    /// @return orderHash The hash of the CoW Swap order that is created to settle the new ETH order.
    function createOrder(EthFlowOrder.Data calldata order)
        external
        payable
        returns (bytes32 orderHash);

    /// @dev Marks an existing ETH flow order as invalid and refunds the trader of all ETH that hasn't been traded yet.
    /// Note that some parameters of the order are ignored, as for example the order expiration date and the quote id.
    ///
    /// @param order The order to be deleted.
    function deleteOrder(EthFlowOrder.Data calldata order) external;

    /// @dev EIP1271-compliant onchain signature verification function.
    /// This function is used by the CoW Swap settlement contract to determine if an order that is signed with an
    /// EIP1271 signature is valid. As this contract has approved the vault relayer contract, a valid signature for an
    /// order means that the order can be traded on CoW Swap.
    ///
    /// @param orderHash Hash of the order to be signed. This is the EIP-712 signing hash for the specified order as
    /// defined in the CoW Swap settlement contract.
    /// @param signature Signature byte array. This parameter is unused since as all information needed to verify if an
    /// order is already available onchain.
    /// @return magicValue Either the EIP-1271 "magic value" indicating success (0x1626ba7e) or a different value
    /// indicating failure (0xffffffff).
    function isValidSignature(bytes32 orderHash, bytes memory signature)
        external
        view
        returns (bytes4 magicValue);
}
