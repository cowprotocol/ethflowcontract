// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "./libraries/EthFlowOrder.sol";
import "./interfaces/ICoWSwapSettlement.sol";
import "./interfaces/ICoWSwapEthFlow.sol";
import "./interfaces/IWrappedNativeToken.sol";
import "./mixins/CoWSwapOnchainOrders.sol";
import "./vendored/GPv2EIP1271.sol";
import "./vendored/ReentrancyGuard.sol";

/// @title CoW Swap ETH Flow
/// @author CoW Swap Developers
contract CoWSwapEthFlow is
    CoWSwapOnchainOrders,
    ReentrancyGuard,
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

    /// @inheritdoc ICoWSwapEthFlow
    function wrap(uint256 amount) external {
        wrappedNativeToken.deposit{value: amount}();
    }

    /// @inheritdoc ICoWSwapEthFlow
    function unwrap(uint256 amount) external {
        wrappedNativeToken.withdraw(amount);
    }

    // The contract needs to be able to receive native tokens when unwrapping.
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    /// @inheritdoc ICoWSwapEthFlow
    function createOrder(EthFlowOrder.Data calldata order)
        external
        payable
        nonReentrant
        returns (bytes32 orderHash)
    {
        if (msg.value != order.sellAmount + order.feeAmount) {
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

    /// @inheritdoc ICoWSwapEthFlow
    function deleteOrder(EthFlowOrder.Data calldata order)
        external
        nonReentrant
    {
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
        (bool success, ) = payable(orderData.owner).call{value: refundAmount}(
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
