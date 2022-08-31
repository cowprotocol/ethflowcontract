// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

// solhint-disable reason-string
// solhint-disable not-rely-on-time

import "forge-std/Test.sol";
import "./Constants.sol";
import "./CoWSwapEthFlow/CoWSwapEthFlowExposed.sol";
import "./FillWithSameByte.sol";
import "./Reverter.sol";
import "../src/interfaces/ICoWSwapOnchainOrders.sol";
import "../src/vendored/GPv2EIP1271.sol";

contract EthFlowTestSetup is Test {
    using EthFlowOrder for EthFlowOrder.Data;
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    struct OrderDetails {
        EthFlowOrder.Data data;
        bytes32 hash;
        bytes orderUid;
    }

    CoWSwapEthFlowExposed internal ethFlow;
    IERC20 internal wrappedNativeToken =
        IERC20(0x1234567890123456789012345678901234567890);
    ICoWSwapSettlement internal cowSwap =
        ICoWSwapSettlement(Constants.COWSWAP_ADDRESS);

    function setUp() public {
        ethFlow = new CoWSwapEthFlowExposed(cowSwap, wrappedNativeToken);
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

    function orderDetails(EthFlowOrder.Data memory order)
        internal
        view
        returns (OrderDetails memory)
    {
        bytes32 orderHash = order.toCoWSwapOrder(wrappedNativeToken).hash(
            ethFlow.cowSwapDomainSeparatorPublic()
        );
        bytes memory orderUid = new bytes(GPv2Order.UID_LENGTH);
        orderUid.packOrderUidParams(
            orderHash,
            address(ethFlow),
            type(uint32).max
        );
        return OrderDetails(order, orderHash, orderUid);
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
}

contract TestOrderCreation is EthFlowTestSetup, ICoWSwapOnchainOrders {
    using EthFlowOrder for EthFlowOrder.Data;
    using GPv2Order for GPv2Order.Data;

    function testRevertOrderCreationIfNotEnoughEthSent() public {
        uint256 sellAmount = 1 ether;
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(address(0)),
            address(0),
            sellAmount,
            0,
            bytes32(0),
            0,
            0,
            false,
            0
        );
        assertEq(order.sellAmount, sellAmount);

        vm.expectRevert(ICoWSwapEthFlow.IncorrectEthAmount.selector);
        ethFlow.createOrder{value: sellAmount - 1}(order);
    }

    function testRevertIfCreatingAnOrderWithTheSameHashTwice() public {
        uint256 sellAmount = 42 ether;
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x01)),
            FillWithSameByte.toAddress(0x02),
            sellAmount,
            FillWithSameByte.toUint256(0x04),
            FillWithSameByte.toBytes32(0x05),
            FillWithSameByte.toUint256(0x06),
            FillWithSameByte.toUint32(0x07),
            true,
            FillWithSameByte.toInt64(0x08)
        );
        assertEq(order.sellAmount, sellAmount);

        bytes32 orderHash = order.toCoWSwapOrder(wrappedNativeToken).hash(
            ethFlow.cowSwapDomainSeparatorPublic()
        );

        address executor1 = address(0x42);
        address executor2 = address(0x1337);
        vm.deal(executor1, sellAmount);
        vm.deal(executor2, sellAmount);

        vm.prank(executor1);
        ethFlow.createOrder{value: sellAmount}(order);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoWSwapEthFlow.OrderIsAlreadyOwned.selector,
                orderHash
            )
        );
        vm.prank(executor2);
        ethFlow.createOrder{value: sellAmount}(order);
    }

    function testOrderCreationReturnsOrderHash() public {
        uint256 sellAmount = 42 ether;
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x01)),
            FillWithSameByte.toAddress(0x02),
            sellAmount,
            FillWithSameByte.toUint256(0x04),
            FillWithSameByte.toBytes32(0x05),
            FillWithSameByte.toUint256(0x06),
            FillWithSameByte.toUint32(0x07),
            true,
            FillWithSameByte.toInt64(0x08)
        );
        assertEq(order.sellAmount, sellAmount);

        bytes32 orderHash = order.toCoWSwapOrder(wrappedNativeToken).hash(
            ethFlow.cowSwapDomainSeparatorPublic()
        );

        assertEq(ethFlow.createOrder{value: sellAmount}(order), orderHash);
    }

    function testOrderCreationEventHasExpectedParams() public {
        uint256 sellAmount = 42 ether;
        uint32 validTo = FillWithSameByte.toUint32(0x01);
        int64 quoteId = 1337;
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x02)),
            FillWithSameByte.toAddress(0x03),
            sellAmount,
            FillWithSameByte.toUint256(0x04),
            FillWithSameByte.toBytes32(0x05),
            FillWithSameByte.toUint256(0x06),
            validTo,
            true,
            quoteId
        );
        assertEq(order.sellAmount, sellAmount);
        assertEq(order.validTo, validTo);

        ICoWSwapOnchainOrders.OnchainSignature
            memory signature = ICoWSwapOnchainOrders.OnchainSignature(
                ICoWSwapOnchainOrders.OnchainSigningScheme.Eip1271,
                abi.encodePacked(address(ethFlow))
            );

        address executor = address(0x1337);
        vm.deal(executor, sellAmount);
        vm.expectEmit(true, true, true, true, address(ethFlow));
        emit ICoWSwapOnchainOrders.OrderPlacement(
            executor,
            order.toCoWSwapOrder(wrappedNativeToken),
            signature,
            abi.encodePacked(quoteId, validTo)
        );
        vm.prank(executor);
        ethFlow.createOrder{value: sellAmount}(order);
    }

    function testOrderCreationSetsExpectedOnchainOrderInformation() public {
        uint256 sellAmount = 42 ether;
        uint32 validTo = FillWithSameByte.toUint32(0x01);
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x02)),
            FillWithSameByte.toAddress(0x03),
            sellAmount,
            FillWithSameByte.toUint256(0x04),
            FillWithSameByte.toBytes32(0x05),
            FillWithSameByte.toUint256(0x06),
            validTo,
            true,
            FillWithSameByte.toInt64(0x07)
        );
        assertEq(order.sellAmount, sellAmount);
        assertEq(order.validTo, validTo);

        bytes32 orderHash = order.toCoWSwapOrder(wrappedNativeToken).hash(
            ethFlow.cowSwapDomainSeparatorPublic()
        );

        address executor = address(0x1337);
        vm.deal(executor, sellAmount);
        vm.prank(executor);
        ethFlow.createOrder{value: sellAmount}(order);

        (address ethFlowOwner, uint32 ethFlowValidTo) = ethFlow.orders(
            orderHash
        );
        assertEq(ethFlowOwner, executor);
        assertEq(ethFlowValidTo, validTo);
    }
}

contract OrderDeletion is EthFlowTestSetup {
    function dummyOrder() internal view returns (EthFlowOrder.Data memory) {
        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(FillWithSameByte.toAddress(0x01)),
            FillWithSameByte.toAddress(0x02),
            FillWithSameByte.toUint256(0x03),
            FillWithSameByte.toUint256(0x04),
            FillWithSameByte.toBytes32(0x05),
            FillWithSameByte.toUint256(0x06),
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
        vm.deal(owner, order.data.sellAmount);
        vm.prank(owner);
        ethFlow.createOrder{value: order.data.sellAmount}(order.data);
    }

    function testCanDeleteValidOrdersIfOwner() public {
        address owner = address(0x424242);
        EthFlowOrder.Data memory ethFlowOrder = dummyOrder();
        OrderDetails memory order = orderDetails(ethFlowOrder);
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.prank(owner);
        ethFlow.deleteOrder(order.data);
    }

    function testCanDeleteExpiredOrdersIfNotOwner() public {
        address owner = address(0x424242);
        address executor = address(0x1337);
        EthFlowOrder.Data memory ethFlowOrder = dummyOrder();
        ethFlowOrder.validTo = uint32(block.timestamp) - 1;
        OrderDetails memory order = orderDetails(ethFlowOrder);
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.prank(executor);
        ethFlow.deleteOrder(order.data);
    }

    function testCannotDeleteValidOrdersIfNotOwner() public {
        address owner = address(0x424242);
        address executor = address(0x1337);
        EthFlowOrder.Data memory ethFlowOrder = dummyOrder();
        ethFlowOrder.validTo = uint32(block.timestamp) + 1;
        OrderDetails memory order = orderDetails(ethFlowOrder);
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoWSwapEthFlow.NotAllowedToDeleteOrder.selector,
                order.hash
            )
        );
        vm.prank(executor);
        ethFlow.deleteOrder(order.data);
    }

    function testOrderDeletionSetsOrderAsInvalidated() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder());
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        assertEq(ordersMapping(order.hash).owner, owner);
        vm.prank(owner);
        ethFlow.deleteOrder(order.data);
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
        OrderDetails memory order = orderDetails(ethFlowOrder);
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        assertEq(owner.balance, 0);
        vm.prank(executor);
        ethFlow.deleteOrder(order.data);
        assertEq(owner.balance, order.data.sellAmount);
    }

    function testOrderDeletionRevertsIfDeletingUninitializedOrder() public {
        OrderDetails memory order = orderDetails(dummyOrder());

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoWSwapEthFlow.NotAllowedToDeleteOrder.selector,
                order.hash
            )
        );
        ethFlow.deleteOrder(order.data);
    }

    function testOrderDeletionRevertsIfDeletingOrderTwice() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder());
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.startPrank(owner);

        ethFlow.deleteOrder(order.data);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoWSwapEthFlow.NotAllowedToDeleteOrder.selector,
                order.hash
            )
        );
        ethFlow.deleteOrder(order.data);

        vm.stopPrank();
    }

    function testOrderDeletionForPartiallyFilledOrders() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder());
        createOrderWithOwner(order, owner);
        uint256 filledAmount = 1337;
        mockOrderFilledAmount(order.orderUid, filledAmount);

        assertEq(owner.balance, 0);
        vm.prank(owner);
        ethFlow.deleteOrder(order.data);
        assertEq(owner.balance, order.data.sellAmount - filledAmount);
    }

    function testOrderDeletionRevertsIfSendingEthFails() public {
        address owner = address(new Reverter());
        OrderDetails memory order = orderDetails(dummyOrder());
        createOrderWithOwner(order, owner);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.expectRevert(ICoWSwapEthFlow.EthTransferFailed.selector);
        vm.prank(owner);
        ethFlow.deleteOrder(order.data);
    }

    function testCannotCreateSameOrderOnceDeleted() public {
        address owner = address(0x424242);
        EthFlowOrder.Data memory ethFlowOrder = dummyOrder();
        ethFlowOrder.validTo = uint32(block.timestamp) - 1;
        OrderDetails memory order = orderDetails(ethFlowOrder);
        mockOrderFilledAmount(order.orderUid, 0);

        vm.deal(owner, order.data.sellAmount);
        vm.startPrank(owner);

        ethFlow.createOrder{value: order.data.sellAmount}(order.data);
        ethFlow.deleteOrder(order.data);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoWSwapEthFlow.OrderIsAlreadyOwned.selector,
                order.hash
            )
        );
        ethFlow.createOrder{value: order.data.sellAmount}(order.data);

        vm.stopPrank();
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
        OrderDetails memory order = orderDetails(dummyOrder());

        assertEq(ethFlow.isValidSignature(order.hash, ""), BAD_SIGNATURE);
    }

    function testGoodSignatureIfOrderIsValid() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder());
        assertGt(order.data.validTo, block.timestamp);

        vm.deal(owner, order.data.sellAmount);
        vm.prank(owner);
        ethFlow.createOrder{value: order.data.sellAmount}(order.data);

        assertEq(
            ethFlow.isValidSignature(order.hash, ""),
            GPv2EIP1271.MAGICVALUE
        );
    }

    function testBadSignatureIfOrderIsExpired() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder());
        assertGt(order.data.validTo, block.timestamp);

        vm.deal(owner, order.data.sellAmount);
        vm.prank(owner);
        ethFlow.createOrder{value: order.data.sellAmount}(order.data);

        vm.warp(order.data.validTo + 1);
        assertLt(order.data.validTo, block.timestamp);

        assertEq(ethFlow.isValidSignature(order.hash, ""), BAD_SIGNATURE);
    }

    function testBadSignatureIfOrderWasDeleted() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder());

        vm.deal(owner, order.data.sellAmount);
        vm.startPrank(owner);

        ethFlow.createOrder{value: order.data.sellAmount}(order.data);
        mockOrderFilledAmount(order.orderUid, 0);
        ethFlow.deleteOrder(order.data);

        vm.stopPrank();

        assertGt(order.data.validTo, block.timestamp); // Ascertain that failure is not caused by an expired order.
        assertEq(ethFlow.isValidSignature(order.hash, ""), BAD_SIGNATURE);
    }
}
