// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

// solhint-disable reason-string
// solhint-disable not-rely-on-time

import "forge-std/Test.sol";
import "./lib/CallOnReceive.sol";
import "./lib/Constants.sol";
import "./lib/CoWSwapEthFlow/CoWSwapEthFlowExposed.sol";
import "./lib/FillWithSameByte.sol";
import "./lib/Reverter.sol";
import "./lib/SendOnUnwrap.sol";
import "../src/interfaces/ICoWSwapOnchainOrders.sol";
import "../src/vendored/GPv2EIP1271.sol";

contract EthFlowTestSetup is Test {
    using EthFlowOrder for EthFlowOrder.Data;
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    struct OrderDetails {
        bytes32 hash;
        EthFlowOrder.Data data;
        bytes orderUid;
        bytes32 cowSwapHash;
    }

    CoWSwapEthFlowExposed internal ethFlow;
    IWrappedNativeToken internal wrappedNativeToken =
        IWrappedNativeToken(0x1234567890123456789012345678901234567890);
    ICoWSwapSettlement internal cowSwap =
        ICoWSwapSettlement(Constants.COWSWAP_SETTLEMENT);
    address internal vaultRelayer = 0x0987654321098765432109876543210987654321;

    function setUp() public {
        vm.mockCall(
            address(cowSwap),
            abi.encodeWithSelector(ICoWSwapSettlement.vaultRelayer.selector),
            abi.encode(vaultRelayer)
        );
        vm.mockCall(
            address(wrappedNativeToken),
            abi.encodeWithSelector(
                IERC20.approve.selector,
                vaultRelayer,
                type(uint256).max
            ),
            abi.encode(true)
        );
        ethFlow = new CoWSwapEthFlowExposed(cowSwap, wrappedNativeToken);
        vm.clearMockedCalls();
    }

    function mockAndExpectCall(
        address to,
        uint256 value,
        bytes memory data,
        bytes memory output
    ) internal {
        vm.mockCall(to, value, data, output);
        vm.expectCall(to, value, data);
    }

    function mockAndExpectCall(
        address to,
        bytes memory data,
        bytes memory output
    ) internal {
        mockAndExpectCall(to, 0, data, output);
    }

    // Unfortunately, even if the order mapping takes a bytes32 and returns a struct, Solidity interprets the output
    // struct as a tuple instead. This wrapping function puts back the ouput into the same struct.
    function ordersMapping(bytes32 orderHash)
        internal
        view
        returns (EthFlowOrder.OnchainData memory)
    {
        (address owner, uint32 validTo) = ethFlow.orders(orderHash);
        return EthFlowOrder.OnchainData(owner, validTo);
    }

    function mockOrderFilledAmount(bytes memory orderUid, uint256 amount)
        public
    {
        vm.mockCall(
            address(cowSwap),
            abi.encodeWithSelector(
                ICoWSwapSettlement.filledAmount.selector,
                orderUid
            ),
            abi.encode(amount)
        );
    }

    function orderDetails(EthFlowOrder.Data memory order, address owner)
        internal
        view
        returns (OrderDetails memory)
    {
        bytes32 cowSwapOrderHash = order
            .toCoWSwapOrder(wrappedNativeToken)
            .hash(ethFlow.cowSwapDomainSeparatorPublic());
        bytes memory orderUid = new bytes(GPv2Order.UID_LENGTH);
        orderUid.packOrderUidParams(
            cowSwapOrderHash,
            address(ethFlow),
            type(uint32).max
        );
        bytes32 orderHash = EthFlowOrder.hash(
            cowSwapOrderHash,
            owner,
            order.validTo
        );
        return OrderDetails(orderHash, order, orderUid, cowSwapOrderHash);
    }
}

contract TestDeployment is EthFlowTestSetup {
    function testDeploymentParams() public {
        assertEq(
            address(ethFlow.wrappedNativeToken()),
            address(wrappedNativeToken)
        );
        assertEq(
            ethFlow.cowSwapDomainSeparatorPublic(),
            Constants.COWSWAP_TEST_DOMAIN_SEPARATOR
        );
    }

    function testSetsWrappedTokenAllowance() public {
        mockAndExpectCall(
            address(cowSwap),
            abi.encodeWithSelector(ICoWSwapSettlement.vaultRelayer.selector),
            abi.encode(vaultRelayer)
        );
        mockAndExpectCall(
            address(wrappedNativeToken),
            abi.encodeWithSelector(
                IERC20.approve.selector,
                vaultRelayer,
                type(uint256).max
            ),
            abi.encode(true)
        );
        ethFlow = new CoWSwapEthFlowExposed(cowSwap, wrappedNativeToken);
        vm.clearMockedCalls();
    }

    function testCanReceiveNativeToken() public {
        uint256 amount = 42 ether;
        address sender = address(1337);
        vm.deal(sender, amount);
        vm.prank(sender);
        payable(address(ethFlow)).transfer(amount);
    }
}

contract TestOrderCreation is EthFlowTestSetup, ICoWSwapOnchainOrders {
    using EthFlowOrder for EthFlowOrder.Data;
    using GPv2Order for GPv2Order.Data;

    function testRevertOrderCreationIfNotEnoughEthSent() public {
        uint256 sellAmount = 41 ether;
        uint256 feeAmount = 1 ether;
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(address(0)),
            address(0),
            sellAmount,
            0,
            bytes32(0),
            feeAmount,
            0,
            false,
            0
        );
        assertEq(order.sellAmount, sellAmount);

        vm.expectRevert(ICoWSwapEthFlow.IncorrectEthAmount.selector);
        ethFlow.createOrder{value: sellAmount + feeAmount - 1}(order);
    }

    function testRevertOrderCreationIfSellAmountIsZero() public {
        uint256 sellAmount = 0 ether;
        uint256 feeAmount = 1 ether;
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(address(0)),
            address(0),
            sellAmount,
            0,
            bytes32(0),
            feeAmount,
            0,
            false,
            0
        );
        assertEq(order.sellAmount, sellAmount);

        vm.expectRevert(ICoWSwapEthFlow.NotAllowedZeroSellAmount.selector);
        ethFlow.createOrder{value: sellAmount + feeAmount}(order);
    }

    function testRevertIfCreatingAnOrderWithTheSameHashTwice() public {
        address executor = address(0x42);
        uint256 sellAmount = 41 ether;
        uint256 feeAmount = 1 ether;
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x01)),
            FillWithSameByte.toAddress(0x02),
            sellAmount,
            FillWithSameByte.toUint256(0x04),
            FillWithSameByte.toBytes32(0x05),
            feeAmount,
            FillWithSameByte.toUint32(0x07),
            true,
            FillWithSameByte.toInt64(0x08)
        );
        assertEq(order.sellAmount, sellAmount);
        assertEq(order.feeAmount, feeAmount);

        bytes32 cowSwapOrderHash = order
            .toCoWSwapOrder(wrappedNativeToken)
            .hash(ethFlow.cowSwapDomainSeparatorPublic());
        bytes32 orderHash = EthFlowOrder.hash(
            cowSwapOrderHash,
            executor,
            order.validTo
        );

        vm.deal(executor, 2 * (sellAmount + feeAmount));

        vm.prank(executor);
        ethFlow.createOrder{value: sellAmount + feeAmount}(order);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoWSwapEthFlow.OrderIsAlreadyOwned.selector,
                orderHash
            )
        );
        vm.prank(executor);
        ethFlow.createOrder{value: sellAmount + feeAmount}(order);
    }

    function testOrderCreationReturnsOrderHash() public {
        uint256 sellAmount = 41 ether;
        uint256 feeAmount = 1 ether;
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x01)),
            FillWithSameByte.toAddress(0x02),
            sellAmount,
            FillWithSameByte.toUint256(0x04),
            FillWithSameByte.toBytes32(0x05),
            feeAmount,
            FillWithSameByte.toUint32(0x07),
            true,
            FillWithSameByte.toInt64(0x08)
        );
        assertEq(order.sellAmount, sellAmount);
        assertEq(order.feeAmount, feeAmount);

        address owner = address(42);
        vm.prank(owner);
        bytes32 cowSwapOrderHash = order
            .toCoWSwapOrder(wrappedNativeToken)
            .hash(ethFlow.cowSwapDomainSeparatorPublic());
        bytes32 orderHash = EthFlowOrder.hash(
            cowSwapOrderHash,
            owner,
            order.validTo
        );

        vm.deal(owner, sellAmount + feeAmount);
        vm.prank(owner);
        assertEq(
            ethFlow.createOrder{value: sellAmount + feeAmount}(order),
            orderHash
        );
    }

    function testOrderCreationEventHasExpectedParams() public {
        uint256 sellAmount = 41 ether;
        uint256 feeAmount = 1 ether;
        uint32 validTo = FillWithSameByte.toUint32(0x01);
        int64 quoteId = 1337;
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x02)),
            FillWithSameByte.toAddress(0x03),
            sellAmount,
            FillWithSameByte.toUint256(0x04),
            FillWithSameByte.toBytes32(0x05),
            feeAmount,
            validTo,
            true,
            quoteId
        );
        assertEq(order.sellAmount, sellAmount);
        assertEq(order.feeAmount, feeAmount);
        assertEq(order.validTo, validTo);

        ICoWSwapOnchainOrders.OnchainSignature
            memory signature = ICoWSwapOnchainOrders.OnchainSignature(
                ICoWSwapOnchainOrders.OnchainSigningScheme.Eip1271,
                abi.encodePacked(address(ethFlow))
            );

        address executor = address(0x1337);
        vm.deal(executor, sellAmount + feeAmount);
        vm.expectEmit(true, true, true, true, address(ethFlow));
        emit ICoWSwapOnchainOrders.OrderPlacement(
            executor,
            order.toCoWSwapOrder(wrappedNativeToken),
            signature,
            abi.encodePacked(quoteId, validTo)
        );
        vm.prank(executor);
        ethFlow.createOrder{value: sellAmount + feeAmount}(order);
    }

    function testOrderCreationSetsExpectedOnchainOrderInformation() public {
        address executor = address(0x1337);
        uint256 sellAmount = 41 ether;
        uint256 feeAmount = 1 ether;
        uint32 validTo = FillWithSameByte.toUint32(0x01);
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x02)),
            FillWithSameByte.toAddress(0x03),
            sellAmount,
            FillWithSameByte.toUint256(0x04),
            FillWithSameByte.toBytes32(0x05),
            feeAmount,
            validTo,
            true,
            FillWithSameByte.toInt64(0x07)
        );
        assertEq(order.sellAmount, sellAmount);
        assertEq(order.feeAmount, feeAmount);
        assertEq(order.validTo, validTo);

        bytes32 cowSwapOrderHash = order
            .toCoWSwapOrder(wrappedNativeToken)
            .hash(ethFlow.cowSwapDomainSeparatorPublic());
        bytes32 orderHash = EthFlowOrder.hash(
            cowSwapOrderHash,
            executor,
            order.validTo
        );

        vm.deal(executor, sellAmount + feeAmount);
        vm.prank(executor);
        ethFlow.createOrder{value: sellAmount + feeAmount}(order);

        (address ethFlowOwner, uint32 ethFlowValidTo) = ethFlow.orders(
            orderHash
        );
        assertEq(ethFlowOwner, executor);
        assertEq(ethFlowValidTo, validTo);
    }

    function testRevertsOnAdditionOverflow() public {
        uint256 sellAmount = type(uint256).max;
        uint256 feeAmount = 1;
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x01)),
            FillWithSameByte.toAddress(0x02),
            sellAmount,
            FillWithSameByte.toUint256(0x03),
            FillWithSameByte.toBytes32(0x04),
            feeAmount,
            FillWithSameByte.toUint32(0x05),
            false,
            FillWithSameByte.toInt64(0x06)
        );
        assertEq(order.sellAmount, sellAmount);
        assertEq(order.feeAmount, feeAmount);

        vm.expectRevert();
        ethFlow.createOrder{value: sellAmount}(order);
    }
}

contract OrderDeletion is
    EthFlowTestSetup,
    ICoWSwapOnchainOrders,
    ICoWSwapEthFlowEvents
{
    function dummyOrder() internal view returns (EthFlowOrder.Data memory) {
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x01)),
            FillWithSameByte.toAddress(0x02),
            FillWithSameByte.toUint128(0x03), // using uint128 to avoid triggering multiplication overflow
            FillWithSameByte.toUint256(0x04),
            FillWithSameByte.toBytes32(0x05),
            FillWithSameByte.toUint128(0x06), // using uint128 to avoid triggering multiplication overflow
            FillWithSameByte.toUint32(0x07),
            true,
            FillWithSameByte.toInt64(0x08)
        );
        require(
            order.validTo > block.timestamp,
            "Dummy order is already expired, please update dummy expiration value"
        );
        return order;
    }

    function createOrderWithOwner(OrderDetails memory order, address owner)
        public
    {
        require(
            (order.data.sellAmount < (1 << 128)) &&
                (order.data.feeAmount < (1 << 128)),
            "The code currently assumes that the sell and fee amounts are not too high. Otherwise, deleting orders causes multiplication overflows."
        );
        vm.deal(owner, order.data.sellAmount + order.data.feeAmount);
        vm.prank(owner);
        ethFlow.createOrder{
            value: order.data.sellAmount + order.data.feeAmount
        }(order.data);
    }

    function testCanInvalidateValidOrdersIfOwner() public {
        address owner = address(0x424242);
        EthFlowOrder.Data memory ethFlowOrder = dummyOrder();
        OrderDetails memory order = orderDetails(ethFlowOrder, owner);
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.prank(owner);
        ethFlow.invalidateOrder(order.data, order.hash);
    }

    function testCanInvalidateExpiredOrdersIfNotOwner() public {
        address owner = address(0x424242);
        address executor = address(0x1337);
        EthFlowOrder.Data memory ethFlowOrder = dummyOrder();
        ethFlowOrder.validTo = uint32(block.timestamp) - 1;
        OrderDetails memory order = orderDetails(ethFlowOrder, owner);
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.prank(executor);
        ethFlow.invalidateOrder(order.data, order.hash);
    }

    function testCanInvalidateOrdersIgnoringNotAllowed() public {
        address owner = address(0x424242);
        address executor = address(0x1337);
        EthFlowOrder.Data[] memory orderArray = new EthFlowOrder.Data[](2);
        bytes32[] memory hashArray = new bytes32[](2);
        orderArray[0] = dummyOrder();
        orderArray[0].validTo = uint32(block.timestamp) - 1;
        OrderDetails memory order1 = orderDetails(orderArray[0], owner);
        hashArray[0] = order1.hash;
        mockOrderFilledAmount(order1.orderUid, 0);
        createOrderWithOwner(order1, owner);
        orderArray[1] = dummyOrder();
        orderArray[1].validTo = uint32(block.timestamp) - 1;
        orderArray[1].sellAmount = orderArray[1].sellAmount + 1;
        OrderDetails memory order2 = orderDetails(orderArray[1], owner);
        hashArray[1] = order2.hash;
        createOrderWithOwner(order2, owner);
        mockOrderFilledAmount(order2.orderUid, 0);

        vm.prank(executor);
        ethFlow.invalidateOrdersIgnoringNotAllowed(orderArray, hashArray);
        assertEq(
            ordersMapping(order1.hash).owner,
            EthFlowOrder.INVALIDATED_OWNER
        );
        assertEq(
            ordersMapping(order2.hash).owner,
            EthFlowOrder.INVALIDATED_OWNER
        );
        EthFlowOrder.Data[] memory orderArray2 = new EthFlowOrder.Data[](3);
        bytes32[] memory hashArray2 = new bytes32[](3);
        orderArray2[0] = orderArray[0];
        hashArray2[0] = hashArray[0];
        orderArray2[1] = orderArray[1];
        hashArray2[1] = hashArray[1];
        // And we can even invalidate a list of orders if some have already been invalidated previously
        orderArray2[2] = dummyOrder();
        orderArray2[2].validTo = uint32(block.timestamp) - 1;
        orderArray2[2].sellAmount = FillWithSameByte.toUint128(0x11);
        OrderDetails memory order3 = orderDetails(orderArray2[2], owner);
        hashArray2[2] = order3.hash;
        createOrderWithOwner(order3, owner);
        mockOrderFilledAmount(order3.orderUid, 0);
        ethFlow.invalidateOrdersIgnoringNotAllowed(orderArray2, hashArray2);
        assertEq(
            ordersMapping(order3.hash).owner,
            EthFlowOrder.INVALIDATED_OWNER
        );
    }

    function testEmitsEventForExpiredOrder() public {
        address owner = address(0x424242);
        address executor = address(0x1337);
        EthFlowOrder.Data memory ethFlowOrder = dummyOrder();
        ethFlowOrder.validTo = uint32(block.timestamp) - 1;
        OrderDetails memory order = orderDetails(ethFlowOrder, owner);
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.expectEmit(true, true, true, true, address(ethFlow));
        emit ICoWSwapEthFlowEvents.OrderRefund(order.orderUid, executor);

        vm.prank(executor);
        ethFlow.invalidateOrder(order.data, order.hash);
    }

    function testEmitsEventForValidOrderDeletion() public {
        address owner = address(0x424242);
        EthFlowOrder.Data memory ethFlowOrder = dummyOrder();
        ethFlowOrder.validTo = uint32(block.timestamp) + 1;
        OrderDetails memory order = orderDetails(ethFlowOrder, owner);
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.expectEmit(true, true, true, true, address(ethFlow));
        emit ICoWSwapOnchainOrders.OrderInvalidation(order.orderUid);

        vm.prank(owner);
        ethFlow.invalidateOrder(order.data, order.hash);
    }

    function testCannotInvalidateValidOrdersIfNotOwner() public {
        address owner = address(0x424242);
        address executor = address(0x1337);
        EthFlowOrder.Data memory ethFlowOrder = dummyOrder();
        ethFlowOrder.validTo = uint32(block.timestamp) + 1;
        OrderDetails memory order = orderDetails(ethFlowOrder, owner);
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoWSwapEthFlow.NotAllowedToInvalidateOrder.selector,
                order.hash
            )
        );
        vm.prank(executor);
        ethFlow.invalidateOrder(order.data, order.hash);
    }

    function testOrderDeletionSetsOrderAsInvalidated() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder(), owner);
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        assertEq(ordersMapping(order.hash).owner, owner);
        vm.prank(owner);
        ethFlow.invalidateOrder(order.data, order.hash);
        assertEq(
            ordersMapping(order.hash).owner,
            EthFlowOrder.INVALIDATED_OWNER
        );
    }

    function testOrderDeletionSendsEthBack() public {
        // Using owner != executor to make certain that the ETH were not sent to msg.sender
        address owner = address(0x424242);
        address executor = address(0x1337);
        EthFlowOrder.Data memory ethFlowOrder = dummyOrder();
        ethFlowOrder.validTo = uint32(block.timestamp) - 1;
        OrderDetails memory order = orderDetails(ethFlowOrder, owner);
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        assertEq(owner.balance, 0);
        vm.prank(executor);
        ethFlow.invalidateOrder(order.data, order.hash);
        assertEq(owner.balance, order.data.sellAmount + order.data.feeAmount);
    }

    function testOrderDeletionRevertsIfDeletingUninitializedOrder() public {
        OrderDetails memory order = orderDetails(
            dummyOrder(),
            EthFlowOrder.NO_OWNER
        );
        // Note: if the order was never created, then the owner is NO_OWNER and validTo is zero.
        bytes32 nulledHash = EthFlowOrder.hash(
            order.cowSwapHash,
            EthFlowOrder.NO_OWNER,
            uint32(0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoWSwapEthFlow.NotAllowedToInvalidateOrder.selector,
                nulledHash
            )
        );
        ethFlow.invalidateOrder(order.data, nulledHash);
    }

    function testOrderDeletionRevertsIfDeletingOrderTwice() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder(), owner);
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.startPrank(owner);

        ethFlow.invalidateOrder(order.data, order.hash);

        // The hash changed, since the owner of the order has changed onchain. Note that order validity didn't change.
        bytes32 updatedHash = EthFlowOrder.hash(
            order.cowSwapHash,
            EthFlowOrder.INVALIDATED_OWNER,
            order.data.validTo
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoWSwapEthFlow.NotAllowedToInvalidateOrder.selector,
                updatedHash
            )
        );
        ethFlow.invalidateOrder(order.data, order.hash);

        vm.stopPrank();
    }

    function testOrderDeletionForPartiallyFilledOrders() public {
        address owner = address(0x424242);
        EthFlowOrder.Data memory order = dummyOrder();
        order.sellAmount = 10 ether;
        order.feeAmount = 1 ether;
        OrderDetails memory orderDetails = orderDetails(order, owner);

        createOrderWithOwner(orderDetails, owner);
        uint256 filledAmount = 2 ether + 1; // does not divide sellAmount to test rounding
        uint256 remainingSellAmount = 8 ether - 1;
        uint256 remainingFeeAmount = 0.8 ether;
        mockOrderFilledAmount(orderDetails.orderUid, filledAmount);

        assertEq(owner.balance, 0);
        vm.prank(owner);
        ethFlow.invalidateOrder(order, orderDetails.hash);
        assertEq(owner.balance, remainingSellAmount + remainingFeeAmount);
    }

    function testOrderDeletionRevertsIfSendingEthFails() public {
        address owner = address(new Reverter());
        OrderDetails memory order = orderDetails(dummyOrder(), owner);
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.expectRevert(ICoWSwapEthFlow.EthTransferFailed.selector);
        vm.prank(owner);
        ethFlow.invalidateOrder(order.data, order.hash);
    }

    function testCannotCreateSameOrderOnceInvalidated() public {
        address owner = address(0x424242);
        EthFlowOrder.Data memory ethFlowOrder = dummyOrder();
        ethFlowOrder.validTo = uint32(block.timestamp) - 1;
        OrderDetails memory order = orderDetails(ethFlowOrder, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.deal(owner, order.data.sellAmount + order.data.feeAmount);
        vm.startPrank(owner);

        ethFlow.createOrder{
            value: order.data.sellAmount + order.data.feeAmount
        }(order.data);
        ethFlow.invalidateOrder(order.data, order.hash);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoWSwapEthFlow.OrderIsAlreadyOwned.selector,
                order.hash
            )
        );
        ethFlow.createOrder{
            value: order.data.sellAmount + order.data.feeAmount
        }(order.data);

        vm.stopPrank();
    }

    function testWethUnwrappingIfContractDoesNotHaveEnoughEth() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder(), owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.deal(owner, order.data.sellAmount + order.data.feeAmount);
        vm.prank(owner);
        ethFlow.createOrder{
            value: order.data.sellAmount + order.data.feeAmount
        }(order.data);

        // Burn some eth
        uint256 burntAmount = 42 ether;
        vm.prank(address(ethFlow));
        payable(address(0)).transfer(burntAmount);

        assertEq(
            address(ethFlow).balance,
            order.data.sellAmount + order.data.feeAmount - burntAmount
        );
        vm.expectCall(
            address(wrappedNativeToken),
            abi.encodeCall(IWrappedNativeToken.withdraw, burntAmount)
        );
        // SendOnUnwrap transfers ETH to the sender on `.unwrap()`.
        vm.deal(address(wrappedNativeToken), burntAmount);
        vm.etch(address(wrappedNativeToken), type(SendOnUnwrap).runtimeCode);

        vm.prank(owner);
        ethFlow.invalidateOrder(order.data, order.hash);
    }
}

contract SignatureVerification is EthFlowTestSetup {
    bytes4 internal constant BAD_SIGNATURE = 0xffffffff;

    function dummyOrder() internal view returns (EthFlowOrder.Data memory) {
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x11)),
            FillWithSameByte.toAddress(0x12),
            FillWithSameByte.toUint256(0x13),
            FillWithSameByte.toUint256(0x14),
            FillWithSameByte.toBytes32(0x15),
            FillWithSameByte.toUint256(0x16),
            FillWithSameByte.toUint32(0x17),
            true,
            FillWithSameByte.toInt64(0x18)
        );
        require(
            order.validTo > block.timestamp,
            "Dummy order is already expired, please update dummy expiration value"
        );
        return order;
    }

    function testBadSignatureIfOrderWasNotCreatedYet() public {
        OrderDetails memory order = orderDetails(dummyOrder(), address(0));
        // Note: if the order was never created, then the owner is NO_OWNER and validTo is zero.
        bytes32 nulledHash = EthFlowOrder.hash(
            order.cowSwapHash,
            EthFlowOrder.NO_OWNER,
            uint32(0)
        );

        assertEq(
            ethFlow.isValidSignature(order.cowSwapHash, abi.encode(nulledHash)),
            BAD_SIGNATURE
        );
    }

    function testGoodSignatureIfOrderIsValid() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder(), owner);
        assertGt(order.data.validTo, block.timestamp);

        vm.deal(owner, order.data.sellAmount + order.data.feeAmount);
        vm.prank(owner);
        ethFlow.createOrder{
            value: order.data.sellAmount + order.data.feeAmount
        }(order.data);

        assertEq(
            ethFlow.isValidSignature(order.cowSwapHash, abi.encode(order.hash)),
            GPv2EIP1271.MAGICVALUE
        );
    }

    function testBadSignatureIfOrderIsExpired() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder(), owner);
        assertGt(order.data.validTo, block.timestamp);

        vm.deal(owner, order.data.sellAmount + order.data.feeAmount);
        vm.prank(owner);
        ethFlow.createOrder{
            value: order.data.sellAmount + order.data.feeAmount
        }(order.data);

        vm.warp(order.data.validTo + 1);
        assertLt(order.data.validTo, block.timestamp);

        assertEq(
            ethFlow.isValidSignature(order.cowSwapHash, abi.encode(order.hash)),
            BAD_SIGNATURE
        );
    }

    function testBadSignatureIfOrderWasInvalidated() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder(), owner);

        vm.deal(owner, order.data.sellAmount + order.data.feeAmount);
        vm.startPrank(owner);

        ethFlow.createOrder{
            value: order.data.sellAmount + order.data.feeAmount
        }(order.data);
        mockOrderFilledAmount(order.orderUid, 0);
        ethFlow.invalidateOrder(order.data, order.hash);

        vm.stopPrank();

        assertEq(
            ordersMapping(order.hash).owner,
            EthFlowOrder.INVALIDATED_OWNER
        ); // Ascertain that failure is not caused by an expired order.
        assertGt(order.data.validTo, block.timestamp); // Ascertain that failure is not caused by an expired order.
        assertEq(
            ethFlow.isValidSignature(order.cowSwapHash, abi.encode(order.hash)),
            BAD_SIGNATURE
        );
    }
}

contract WrapUnwrap is EthFlowTestSetup {
    function testWrapAllCallsWrappedToken() public {
        uint256 wrapAmount = 1337 ether;
        vm.deal(address(ethFlow), wrapAmount);
        assertEq(address(ethFlow).balance, wrapAmount);

        mockAndExpectCall(
            address(wrappedNativeToken),
            wrapAmount,
            hex"",
            hex""
        );
        ethFlow.wrapAll();
    }

    function testWrappingCallsWrappedToken() public {
        uint256 wrapAmount = 1337 ether;

        mockAndExpectCall(
            address(wrappedNativeToken),
            wrapAmount,
            hex"",
            hex""
        );
        ethFlow.wrap(wrapAmount);
    }

    function testUnwrappingCallsWrappedToken() public {
        uint256 unwrapAmount = 1337 ether;
        mockAndExpectCall(
            address(wrappedNativeToken),
            abi.encodeCall(IWrappedNativeToken.withdraw, unwrapAmount),
            hex""
        );
        ethFlow.unwrap(unwrapAmount);
    }
}
