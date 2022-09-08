// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

// solhint-disable reason-string
// solhint-disable not-rely-on-time

import "forge-std/Test.sol";
import "./Constants.sol";
import "./CoWSwapEthFlow/CoWSwapEthFlowExposed.sol";
import "./FillWithSameByte.sol";
import "./CallOnReceive.sol";
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

    function testRevertIfCreatingAnOrderWithTheSameHashTwice() public {
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

        bytes32 orderHash = order.toCoWSwapOrder(wrappedNativeToken).hash(
            ethFlow.cowSwapDomainSeparatorPublic()
        );

        address executor1 = address(0x42);
        address executor2 = address(0x1337);
        vm.deal(executor1, sellAmount + feeAmount);
        vm.deal(executor2, sellAmount + feeAmount);

        vm.prank(executor1);
        ethFlow.createOrder{value: sellAmount + feeAmount}(order);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICoWSwapEthFlow.OrderIsAlreadyOwned.selector,
                orderHash
            )
        );
        vm.prank(executor2);
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

        bytes32 orderHash = order.toCoWSwapOrder(wrappedNativeToken).hash(
            ethFlow.cowSwapDomainSeparatorPublic()
        );

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

        bytes32 orderHash = order.toCoWSwapOrder(wrappedNativeToken).hash(
            ethFlow.cowSwapDomainSeparatorPublic()
        );

        address executor = address(0x1337);
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

contract OrderDeletion is EthFlowTestSetup {
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
        assertEq(owner.balance, order.data.sellAmount + order.data.feeAmount);
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
        EthFlowOrder.Data memory order = dummyOrder();
        order.sellAmount = 10 ether;
        order.feeAmount = 1 ether;
        OrderDetails memory orderDetails = orderDetails(order);

        createOrderWithOwner(orderDetails, owner);
        uint256 filledAmount = 2 ether + 1; // does not divide sellAmount to test rounding
        uint256 remainingSellAmount = 8 ether - 1;
        uint256 remainingFeeAmount = 0.8 ether;
        mockOrderFilledAmount(orderDetails.orderUid, filledAmount);

        assertEq(owner.balance, 0);
        vm.prank(owner);
        ethFlow.deleteOrder(order);
        assertEq(owner.balance, remainingSellAmount + remainingFeeAmount);
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

        vm.deal(owner, order.data.sellAmount + order.data.feeAmount);
        vm.startPrank(owner);

        ethFlow.createOrder{
            value: order.data.sellAmount + order.data.feeAmount
        }(order.data);
        ethFlow.deleteOrder(order.data);
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

    function testNonReentrant() public {
        CallOnReceive owner = new CallOnReceive();
        EthFlowOrder.Data memory ethFlowOrder1 = dummyOrder();
        EthFlowOrder.Data memory ethFlowOrder2 = dummyOrder();
        ethFlowOrder1.appData ^= bytes32(type(uint256).max); // Change any parameter to get a different order.
        OrderDetails memory orderDetails1 = orderDetails(ethFlowOrder1);

        // Create first order
        vm.deal(
            address(owner),
            ethFlowOrder1.sellAmount + ethFlowOrder1.feeAmount
        );
        owner.execCall(
            payable(address(ethFlow)),
            ethFlowOrder1.sellAmount + ethFlowOrder1.feeAmount,
            abi.encodeCall(ethFlow.createOrder, ethFlowOrder1)
        );

        // Prepare creating second order on reentrancy. CallOnReceive is configured to execute that call. It does *not*
        // revert if the call reverts but store the result of the call in storage.
        vm.deal(address(owner), ethFlowOrder2.sellAmount);
        owner.setCallOnReceive(
            payable(address(ethFlow)),
            ethFlowOrder2.sellAmount + ethFlowOrder2.feeAmount,
            abi.encodeCall(ethFlow.createOrder, ethFlowOrder2)
        );

        // Delete order with attempted reentrancy.
        mockOrderFilledAmount(orderDetails1.orderUid, 0);
        owner.execCall(
            payable(address(ethFlow)),
            0,
            abi.encodeCall(ethFlow.deleteOrder, ethFlowOrder1)
        );

        assertFalse(owner.lastFallbackCallSuccess());
        bytes memory reentrancyRevertData = abi.encodeWithSignature(
            "Error(string)", // https://docs.soliditylang.org/en/v0.8.16/control-structures.html?highlight=%22Error(string)%22#panic-via-assert-and-error-via-require
            "ReentrancyGuard: reentrant call"
        );
        assertEq(owner.lastFallbackCallReturnData(), reentrancyRevertData);
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

        vm.deal(owner, order.data.sellAmount + order.data.feeAmount);
        vm.prank(owner);
        ethFlow.createOrder{
            value: order.data.sellAmount + order.data.feeAmount
        }(order.data);

        assertEq(
            ethFlow.isValidSignature(order.hash, ""),
            GPv2EIP1271.MAGICVALUE
        );
    }

    function testBadSignatureIfOrderIsExpired() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder());
        assertGt(order.data.validTo, block.timestamp);

        vm.deal(owner, order.data.sellAmount + order.data.feeAmount);
        vm.prank(owner);
        ethFlow.createOrder{
            value: order.data.sellAmount + order.data.feeAmount
        }(order.data);

        vm.warp(order.data.validTo + 1);
        assertLt(order.data.validTo, block.timestamp);

        assertEq(ethFlow.isValidSignature(order.hash, ""), BAD_SIGNATURE);
    }

    function testBadSignatureIfOrderWasDeleted() public {
        address owner = address(0x424242);
        OrderDetails memory order = orderDetails(dummyOrder());

        vm.deal(owner, order.data.sellAmount + order.data.feeAmount);
        vm.startPrank(owner);

        ethFlow.createOrder{
            value: order.data.sellAmount + order.data.feeAmount
        }(order.data);
        mockOrderFilledAmount(order.orderUid, 0);
        ethFlow.deleteOrder(order.data);

        vm.stopPrank();

        assertGt(order.data.validTo, block.timestamp); // Ascertain that failure is not caused by an expired order.
        assertEq(ethFlow.isValidSignature(order.hash, ""), BAD_SIGNATURE);
    }
}
