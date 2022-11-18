// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "./libraries/EthFlowOrder.sol";
import "./interfaces/ICoWSwapSettlement.sol";
import "./interfaces/ICoWSwapEthFlow.sol";
import "./interfaces/IWrappedNativeToken.sol";
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
    IWrappedNativeToken public immutable wrappedNativeToken;

    /// @dev Each ETH flow order as described in [`EthFlowOrder.Data`] can be converted to a CoW Swap order. Distinct
    /// CoW Swap orders have non-colliding order hashes. This mapping associates some extra data to a specific CoW Swap
    /// order. This data is stored onchain and is used to verify the ownership and validity of an ETH flow order.
    /// An ETH flow order can be settled onchain only if converting it to a CoW Swap order and hashing yields valid
    /// onchain data.
    mapping(bytes32 => EthFlowOrder.OnchainData) public orders;

    /// @param _cowSwapSettlement The CoW Swap settlement contract.
    /// @param _wrappedNativeToken The default native token in the current chain (e.g., WETH on mainnet).
    constructor(
        ICoWSwapSettlement _cowSwapSettlement,
        IWrappedNativeToken _wrappedNativeToken
    ) CoWSwapOnchainOrders(address(_cowSwapSettlement)) {
        cowSwapSettlement = _cowSwapSettlement;
        wrappedNativeToken = _wrappedNativeToken;

        _wrappedNativeToken.approve(
            cowSwapSettlement.vaultRelayer(),
            type(uint256).max
        );
    }

    // The contract needs to be able to receive native tokens when unwrapping.
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    /// @inheritdoc ICoWSwapEthFlow
    function wrapAll() external {
        wrap(address(this).balance);
    }

    /// @inheritdoc ICoWSwapEthFlow
    function wrap(uint256 amount) public {
        // The fallback implementation of the standard WETH9 contract just calls `deposit`. Using the fallback instead
        // of directly calling `deposit` is slightly cheaper in terms of gas.
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = payable(address(wrappedNativeToken)).call{
            value: amount
        }("");
        // The success value is intentionally disregarded. The callback of the standard WETH9 contract has no revert
        // path in the code, so it could only revert if the internal call runs out of gas. This is not considered a
        // security risk since a reverting internal call would just mean that calling this function has no effect.
        success;
    }

    /// @inheritdoc ICoWSwapEthFlow
    function unwrap(uint256 amount) external {
        wrappedNativeToken.withdraw(amount);
    }

    /// @inheritdoc ICoWSwapEthFlow
    function createOrder(EthFlowOrder.Data calldata order)
        external
        payable
        returns (bytes32 orderHash)
    {
        if (msg.value != order.sellAmount + order.feeAmount) {
            revert IncorrectEthAmount();
        }

        if (0 == order.sellAmount) {
            revert NotAllowedZeroSellAmount();
        }

        address owner = msg.sender;
        uint32 validTo = order.validTo;
        EthFlowOrder.OnchainData memory onchainData = EthFlowOrder.OnchainData(
            owner,
            validTo
        );

        OnchainSignature memory signature = OnchainSignature(
            OnchainSigningScheme.Eip1271,
            abi.encodePacked(address(this))
        );

        // The data event field includes extra information needed to settle orders with the CoW Swap API.
        bytes memory data = abi.encodePacked(order.quoteId, validTo);

        bytes32 cowSwapOrderHash = broadcastOrder(
            owner,
            order.toCoWSwapOrder(wrappedNativeToken),
            signature,
            data
        );
        orderHash = EthFlowOrder.hash(cowSwapOrderHash, owner, validTo);

        if (orders[orderHash].owner != EthFlowOrder.NO_OWNER) {
            revert OrderIsAlreadyOwned(orderHash);
        }

        orders[orderHash] = onchainData;
    }

    /// @inheritdoc ICoWSwapEthFlow
    function invalidateOrdersIgnoringNotAllowed(
        EthFlowOrder.Data[] calldata orderArray,
        bytes32[] calldata providedOrderHashes
    ) external {
        for (uint256 i = 0; i < orderArray.length; i++) {
            _invalidateOrder(orderArray[i], providedOrderHashes[i], false);
        }
    }

    /// @inheritdoc ICoWSwapEthFlow
    function invalidateOrder(
        EthFlowOrder.Data calldata order,
        bytes32 providedOrderHash
    ) public {
        _invalidateOrder(order, providedOrderHash, true);
    }

    /// @dev Performs the same tasks as `invalidateOrder` (see documentation in `ICoWSwapEthFlow`), but also allows the
    /// caller to ignore the revert condition `NotAllowedToInvalidateOrder`. Instead of reverting, it stops execution
    /// without causing any state change.
    ///
    /// @param order order to be invalidated.
    /// @param revertOnInvalidDeletion controls whether the function call should revert or just return.
    function _invalidateOrder(
        EthFlowOrder.Data calldata order,
        bytes32 providedOrderHash,
        bool revertOnInvalidDeletion
    ) internal {
        EthFlowOrder.OnchainData memory providedOrderData = orders[
            providedOrderHash
        ];
        address owner = providedOrderData.owner;
        uint32 validTo = providedOrderData.validTo;

        GPv2Order.Data memory cowSwapOrder = order.toCoWSwapOrder(
            wrappedNativeToken
        );
        bytes32 cowSwapOrderHash = cowSwapOrder.hash(cowSwapDomainSeparator);
        bytes32 orderHash = EthFlowOrder.hash(cowSwapOrderHash, owner, validTo);

        // We test if the order is valid using user provided values. The validity of these values is confirmad by
        // comparing the real and user-provided hash.
        // solhint-disable-next-line not-rely-on-time
        bool isTradable = validTo >= block.timestamp;
        if (
            orderHash != providedOrderHash ||
            owner == EthFlowOrder.NO_OWNER ||
            owner == EthFlowOrder.INVALIDATED_OWNER ||
            (isTradable && owner != msg.sender)
        ) {
            if (revertOnInvalidDeletion) {
                revert NotAllowedToInvalidateOrder(orderHash);
            } else {
                return;
            }
        }
        orders[orderHash].owner = EthFlowOrder.INVALIDATED_OWNER;

        bytes memory orderUid = new bytes(GPv2Order.UID_LENGTH);
        orderUid.packOrderUidParams(
            cowSwapOrderHash,
            address(this),
            cowSwapOrder.validTo
        );

        // solhint-disable-next-line not-rely-on-time
        if (isTradable) {
            // Order is valid but its owner decided to invalidate it.
            emit OrderInvalidation(orderUid);
        } else {
            // The order cannot be traded anymore, so this transaction is likely triggered to get back the ETH. We are
            // interested in knowing who is the source of the refund.
            emit OrderRefund(orderUid, msg.sender);
        }

        uint256 filledAmount = cowSwapSettlement.filledAmount(orderUid);

        // This comment argues that a CoW Swap trader does not pay more fees if a partially fillable order is
        // (partially) settled in multiple batches rather than in one single batch of the combined size.
        // This also means that we can refund the user assuming the worst case of settling the filled amount in a single
        // batch without risking giving out more funds than available in the contract because of rounding issues.
        // A CoW Swap trader is always charged exactly the amount of fees that is proportional to the filled amount
        // rounded down to the smaller integer. The code is here:
        // https://github.com/cowprotocol/contracts/blob/d4e0fcd58367907bf1aff54d182222eeaee793dd/src/contracts/GPv2Settlement.sol#L385-L387
        // We show that a trader pays less in fee to CoW Swap when settiling a partially fillable order in two
        // executions rather than a single one for the combined amount; by induction this proves our original statement.
        // Our previous statement is equivalent to `floor(a/c) + floor(b/c) ≤ floor((a+b)/c)`. Writing a and b in terms
        // of reminders (`a = ad*c+ar`, `b = bd*c+br`) the equation becomes `ad + bd ≤ ad + bd + floor((ar+br)/c)`,
        // which is immediately true.
        uint256 refundAmount;
        unchecked {
            // - Multiplication overflow: since this smart contract never invalidates orders on CoW Swap,
            //   `filledAmount <= sellAmount`. Also, `feeAmount + sellAmount` is an amount of native tokens that was
            //   originally sent by the user. As such, it cannot be larger than the amount of native tokens available,
            //   which is smaller than 2¹²⁸/10¹⁸ ≈ 10²⁰ in all networks supported by CoW Swap so far. Since both values
            //    are smaller than 2¹²⁸, their product does not overflow a uint256.
            // - Subtraction underflow: again `filledAmount ≤ sellAmount`, meaning:
            //   feeAmount * filledAmount / sellAmount ≤ feeAmount
            uint256 feeRefundAmount = cowSwapOrder.feeAmount -
                ((cowSwapOrder.feeAmount * filledAmount) /
                    cowSwapOrder.sellAmount);

            // - Subtraction underflow: as noted before, filledAmount ≤ sellAmount.
            // - Addition overflow: as noted before, the user already sent feeAmount + sellAmount native tokens, which
            //   did not overflow.
            refundAmount =
                cowSwapOrder.sellAmount -
                filledAmount +
                feeRefundAmount;
        }

        // If not enough native token is available in the contract, unwrap the needed amount.
        if (address(this).balance < refundAmount) {
            uint256 withdrawAmount;
            unchecked {
                withdrawAmount = refundAmount - address(this).balance;
            }
            wrappedNativeToken.withdraw(withdrawAmount);
        }

        // Using low level calls to perform the transfer avoids setting arbitrary limits to the amount of gas used in a
        // call. Reentrancy is avoided thanks to the `nonReentrant` function modifier.
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = payable(owner).call{value: refundAmount}("");
        if (!success) {
            revert EthTransferFailed();
        }
    }

    /// @inheritdoc ICoWSwapEthFlow
    function isValidSignature(bytes32 cowSwapOrderHash, bytes memory signature)
        external
        view
        override(EIP1271Verifier, ICoWSwapEthFlow)
        returns (bytes4)
    {
        // Note: the signature is the expected hash of the eth-flow order.
        bytes32 providedOrderHash = abi.decode(signature, (bytes32));
        EthFlowOrder.OnchainData memory providedOrderData = orders[
            providedOrderHash
        ];
        address owner = providedOrderData.owner;
        uint32 validTo = providedOrderData.validTo;
        bytes32 orderHash = EthFlowOrder.hash(cowSwapOrderHash, owner, validTo);

        if (
            (orderHash == providedOrderHash) &&
            (owner != EthFlowOrder.NO_OWNER) &&
            (owner != EthFlowOrder.INVALIDATED_OWNER) &&
            // solhint-disable-next-line not-rely-on-time
            (validTo >= block.timestamp)
        ) {
            return GPv2EIP1271.MAGICVALUE;
        } else {
            return bytes4(type(uint32).max);
        }
    }
}
