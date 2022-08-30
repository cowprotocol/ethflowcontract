// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "./Constants.sol";
import "./CoWSwapEthFlow/CoWSwapEthFlowExposed.sol";
import "./FillWithSameByte.sol";
import "../src/interfaces/ICoWSwapOnchainOrders.sol";

contract TestCoWSwapEthFlow is Test, ICoWSwapOnchainOrders {
    using EthFlowOrder for EthFlowOrder.Data;
    using GPv2Order for GPv2Order.Data;

    CoWSwapEthFlowExposed internal ethFlow;
    IERC20 internal wrappedNativeToken =
        IERC20(0x1234567890123456789012345678901234567890);
    address internal cowSwap = Constants.COWSWAP_ADDRESS;

    function setUp() public {
        ethFlow = new CoWSwapEthFlowExposed(cowSwap, wrappedNativeToken);
    }

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

        vm.startPrank(executor1);
        ethFlow.createOrder{value: sellAmount}(order);
        vm.stopPrank();

        vm.startPrank(executor2);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICoWSwapEthFlow.OrderIsAlreadyOwned.selector,
                orderHash
            )
        );
        ethFlow.createOrder{value: sellAmount}(order);
        vm.stopPrank();
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
        vm.startPrank(executor);
        vm.expectEmit(true, true, true, true, address(ethFlow));
        emit ICoWSwapOnchainOrders.OrderPlacement(
            executor,
            order.toCoWSwapOrder(wrappedNativeToken),
            signature,
            abi.encodePacked(validTo, quoteId)
        );
        ethFlow.createOrder{value: sellAmount}(order);
        vm.stopPrank();
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
        vm.startPrank(executor);
        ethFlow.createOrder{value: sellAmount}(order);
        vm.stopPrank();

        (address ethFlowOwner, uint32 ethFlowValidTo) = ethFlow.orders(
            orderHash
        );
        assertEq(ethFlowOwner, executor);
        assertEq(ethFlowValidTo, validTo);
    }
}
