// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "./libraries/EthFlowOrder.sol";
import "./interfaces/ICoWSwapSettlement.sol";
import "./interfaces/ICoWSwapEthFlow.sol";
import "./mixins/CoWSwapOnchainOrders.sol";
import "./vendored/GPv2EIP1271.sol";

/// @title CoW Swap ETH Flow
/// @author CoW Swap Developers
contract CoWSwapEthFlow is
    CoWSwapOnchainOrders,
    EIP1271Verifier,
    ICoWSwapEthFlow
{
    using EthFlowOrder for EthFlowOrder.Data;
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    /// @dev The address of the CoW Swap settlement contract that will be used to settle orders created by this
    /// contract.
    ICoWSwapSettlement public immutable cowSwapSettlement;

    /// @dev The address of the contract representing the default native token in the current chain (e.g., WETH for
    /// Ethereum mainnet).
    IERC20 public immutable wrappedNativeToken;

    /// @dev Each ETH flow order as described in [`EthFlowOrder.Data`] can be converted to a CoW Swap order. Distinct
    /// CoW Swap orders have non-colliding order hashes. This mapping associates some extra data to a specific CoW Swap
    /// order. This data is stored onchain and is used to verify the ownership and validity of an ETH flow order.
    /// An ETH flow order can be settled onchain only if converting it to a CoW Swap order and hashing yields valid
    /// onchain data.
    mapping(bytes32 => EthFlowOrder.OnchainData) public orders;

    /// @param _cowSwapSettlement The address of the CoW Swap settlement contract.
    /// @param _wrappedNativeToken The address of the default native token in the current chain (e.g., WETH on mainnet).
    constructor(
        ICoWSwapSettlement _cowSwapSettlement,
        IERC20 _wrappedNativeToken
    ) CoWSwapOnchainOrders(address(_cowSwapSettlement)) {
        cowSwapSettlement = _cowSwapSettlement;
        wrappedNativeToken = _wrappedNativeToken;
    }

    /// @inheritdoc ICoWSwapEthFlow
    function createOrder(EthFlowOrder.Data calldata order)
        external
        payable
        returns (bytes32 orderHash)
    {
        if (msg.value != order.sellAmount) {
            revert IncorrectEthAmount();
        }

        EthFlowOrder.OnchainData memory onchainData = EthFlowOrder.OnchainData(
            msg.sender,
            order.validTo
        );

        OnchainSignature memory signature = OnchainSignature(
            OnchainSigningScheme.Eip1271,
            abi.encodePacked(address(this))
        );

        // The data event field includes extra information needed to settle orders with the CoW Swap API.
        bytes memory data = abi.encodePacked(
            onchainData.validTo,
            order.quoteId
        );

        orderHash = broadcastOrder(
            onchainData.owner,
            order.toCoWSwapOrder(wrappedNativeToken),
            signature,
            data
        );

        if (orders[orderHash].owner != EthFlowOrder.NO_OWNER) {
            revert OrderIsAlreadyOwned(orderHash);
        }

        orders[orderHash] = onchainData;
    }

    /// @inheritdoc ICoWSwapEthFlow
    function deleteOrder(EthFlowOrder.Data calldata order) external {
        GPv2Order.Data memory cowSwapOrder = order.toCoWSwapOrder(
            wrappedNativeToken
        );
        bytes32 orderHash = cowSwapOrder.hash(cowSwapDomainSeparator);

        EthFlowOrder.OnchainData memory orderData = orders[orderHash];

        if (
            orderData.owner == EthFlowOrder.INVALIDATED_OWNER ||
            orderData.owner == EthFlowOrder.NO_OWNER ||
            (// solhint-disable-next-line not-rely-on-time
            orderData.validTo >= block.timestamp &&
                orderData.owner != msg.sender)
        ) {
            revert NotAllowedToDeleteOrder(orderHash);
        }

        orders[orderHash].owner = EthFlowOrder.INVALIDATED_OWNER;

        bytes memory orderUid = new bytes(GPv2Order.UID_LENGTH);
        orderUid.packOrderUidParams(
            orderHash,
            address(this),
            cowSwapOrder.validTo
        );
        uint256 freedAmount = cowSwapOrder.sellAmount -
            cowSwapSettlement.filledAmount(orderUid);

        // Using low level calls to perform the transfer avoids setting arbitrary limits to the amount of gas used in a
        // call. The drawback is allowing reentrancy from this point in the contract. Note that the current order was
        // already invalidated and cannot be claimed again. TODO: ensure that this is robust under order updates when
        // implemented.
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = payable(orderData.owner).call{value: freedAmount}(
            ""
        );
        if (!success) {
            revert EthTransferFailed();
        }
    }

    /// @inheritdoc ICoWSwapEthFlow
    function isValidSignature(bytes32 orderHash, bytes memory)
        external
        view
        override(EIP1271Verifier, ICoWSwapEthFlow)
        returns (bytes4)
    {
        // Note: the signature parameter is ignored since all information needed to verify the validity of the order is
        // already available onchain.
        EthFlowOrder.OnchainData memory orderData = orders[orderHash];
        if (
            (orderData.owner != EthFlowOrder.NO_OWNER) &&
            (orderData.owner != EthFlowOrder.INVALIDATED_OWNER) &&
            // solhint-disable-next-line not-rely-on-time
            (orderData.validTo >= block.timestamp)
        ) {
            return GPv2EIP1271.MAGICVALUE;
        } else {
            return bytes4(type(uint32).max);
        }
    }
}
