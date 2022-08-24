// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "./FillWithSameByte.sol";
import "../src/vendored/GPv2Order.sol";
import "../src/libraries/EthFlowOrder.sol";

// Note: inheriting the interface ICoWSwapOnchainOrders allows us to emit the event without redefining it again in this
// contract.
contract TestCoWSwapOnchainOrders is Test {
    using EthFlowOrder for EthFlowOrder.Data;

    function testCoWSwapOrderFields() public {
        EthFlowOrder.Data memory ethFlowOrder = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x01)),
            FillWithSameByte.toAddress(0x02),
            FillWithSameByte.toUint256(0x03),
            FillWithSameByte.toUint256(0x04),
            FillWithSameByte.toBytes32(0x05),
            FillWithSameByte.toUint256(0x06),
            FillWithSameByte.toUint32(0x07),
            true,
            FillWithSameByte.toUint64(0x08)
        );
        IERC20 wrappedNativeToken = IERC20(FillWithSameByte.toAddress(0x42));

        GPv2Order.Data memory cowSwapOrder = ethFlowOrder.toCoWSwapOrder(
            wrappedNativeToken
        );

        assertEq(address(cowSwapOrder.sellToken), address(wrappedNativeToken));
        assertEq(
            address(cowSwapOrder.buyToken),
            address(ethFlowOrder.buyToken)
        );
        assertEq(cowSwapOrder.receiver, ethFlowOrder.receiver);
        assertEq(cowSwapOrder.sellAmount, ethFlowOrder.sellAmount);
        assertEq(cowSwapOrder.buyAmount, ethFlowOrder.buyAmount);
        assertEq(cowSwapOrder.validTo, type(uint32).max);
        assertEq(cowSwapOrder.appData, ethFlowOrder.appData);
        assertEq(cowSwapOrder.feeAmount, ethFlowOrder.feeAmount);
        assertEq(cowSwapOrder.kind, GPv2Order.KIND_SELL);
        assertEq(
            cowSwapOrder.partiallyFillable,
            ethFlowOrder.partiallyFillable
        );
        assertEq(cowSwapOrder.sellTokenBalance, GPv2Order.BALANCE_ERC20);
        assertEq(cowSwapOrder.buyTokenBalance, GPv2Order.BALANCE_ERC20);
    }

    function testRevertIfNoReceiver() public {
        EthFlowOrder.Data memory ethFlowOrder = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x01)),
            GPv2Order.RECEIVER_SAME_AS_OWNER,
            FillWithSameByte.toUint256(0x03),
            FillWithSameByte.toUint256(0x04),
            FillWithSameByte.toBytes32(0x05),
            FillWithSameByte.toUint256(0x06),
            FillWithSameByte.toUint32(0x07),
            true,
            FillWithSameByte.toUint32(0x08)
        );
        assertEq(ethFlowOrder.receiver, GPv2Order.RECEIVER_SAME_AS_OWNER);

        IERC20 wrappedNativeToken = IERC20(FillWithSameByte.toAddress(0x42));

        vm.expectRevert(EthFlowOrder.ReceiverMustBeSet.selector);

        ethFlowOrder.toCoWSwapOrder(wrappedNativeToken);
    }
}
