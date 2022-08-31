// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "./libraries/EthFlowOrder.sol";
import "./interfaces/ICoWSwapEthFlow.sol";
import "./mixins/CoWSwapOnchainOrders.sol";

/// @title CoW Swap ETH Flow
/// @author CoW Swap Developers
contract CoWSwapEthFlow is CoWSwapOnchainOrders, ICoWSwapEthFlow {
    using EthFlowOrder for EthFlowOrder.Data;

    /// @dev The address of the contract representing the default native token in the current chain (e.g., WETH for
    /// Ethereum mainnet).
    IERC20 public immutable wrappedNativeToken;

    /// @dev Each ETH flow order as described in [`EthFlowOrder.Data`] can be converted to a CoW Swap order. Distinct
    /// CoW Swap orders have non-colliding order hashes. This mapping associates some extra data to a specific CoW Swap
    /// order. This data is stored onchain and is used to verify the ownership and validity of an ETH flow order.
    /// An ETH flow order can be settled onchain only if converting it to a CoW Swap order and hashing yields valid
    /// onchain data.
    mapping(bytes32 => EthFlowOrder.OnchainData) public orders;

    /// @param _cowSwapSettlementContract The address of the CoW Swap settlement contract.
    /// @param _wrappedNativeToken The address of the default native token in the current chain (e.g., WETH on mainnet).
    constructor(address _cowSwapSettlementContract, IERC20 _wrappedNativeToken)
        CoWSwapOnchainOrders(_cowSwapSettlementContract)
    {
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
            order.quoteId,
            onchainData.validTo
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
}
