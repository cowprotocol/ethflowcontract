// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "../src/vendored/IERC20.sol";
import "../src/interfaces/IWETH.sol";
import "../src/interfaces/ISettlement.sol";
import "../src/libraries/CowSwapOnchainOrder.sol";
import "../src/vendored/GPv2Order.sol";
import "../src/CoWSwapETHFlow.sol";
import "../src/CowSwapOnchainOrderBroadcaster.sol";
import "forge-std/console.sol";

contract TestCoWSwapETHFlow is Test {
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    CoWSwapETHFlow public ethflow;
    CowSwapOnchainOrderBroadcaster public broadcaster;
    ISettlement public settlement;
    IWETH public weth;
    address public allowance_manager;

    function setUp() public {
        settlement = ISettlement(address(10));
        weth = IWETH(address(11));
        allowance_manager = address(12);
        vm.mockCall(
            address(weth),
            abi.encodeWithSelector(
                IWETH.approve.selector,
                address(allowance_manager),
                type(uint256).max
            ),
            abi.encode(true)
        );
        broadcaster = new CowSwapOnchainOrderBroadcaster(settlement);
        ethflow = new CoWSwapETHFlow(weth, allowance_manager, settlement);
    }

    function helperCreateTestOrderData()
        public
        pure
        returns (GPv2Order.Data memory)
    {
        uint32 validTo = 500000;
        // set current timestamp such that validTo is in the future
        uint256 sell_amount = 2;
        return
            GPv2Order.Data(
                IERC20(address(1)),
                IERC20(address(2)),
                address(1),
                sell_amount,
                1,
                validTo,
                bytes32(0),
                1,
                GPv2Order.KIND_SELL,
                false,
                bytes32(0),
                bytes32(0)
            );
    }

    function testOrderCreationSuccessfully() public {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        vm.warp(order.validTo - 60 * 30);
        uint64 quoteId = uint64(0);
        ethflow.createOrder{value: order.sellAmount}(order, quoteId);
    }

    function testOrderCreationChecksThatValidToAndUserAreStoredCorrectly()
        public
    {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        vm.warp(order.validTo - 60 * 30);
        uint64 quoteId = uint64(0);
        ethflow.createOrder{value: order.sellAmount}(order, quoteId);
        uint32 validTo = order.validTo;
        GPv2Order.Data memory modified_order_of_ethflow_contract = order;
        modified_order_of_ethflow_contract.validTo = type(uint32).max;
        bytes32 expected_stored_value = bytes32(
            abi.encodePacked(validTo, address(this))
        );
        assertEq(
            ethflow.orders(
                modified_order_of_ethflow_contract.hash(
                    CowSwapEip712.domainSeparator()
                )
            ),
            expected_stored_value
        );
    }

    function testOrderCreationSendsEthToWethContract() public {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        uint64 quoteId = uint64(0);
        vm.warp(order.validTo - 60 * 30);
        ethflow.createOrder{value: order.sellAmount}(order, quoteId);
        assertEq(address(weth).balance, order.sellAmount);
    }

    function testOrderCreationCannotCreateOrderTwice() public {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        uint64 quoteId = uint64(0);
        vm.warp(order.validTo - 60 * 30);
        ethflow.createOrder{value: order.sellAmount}(order, quoteId);
        vm.expectRevert("order already existing");
        ethflow.createOrder{value: order.sellAmount}(order, quoteId);
    }

    function testOrderCreationEmitsEvent() public {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        vm.warp(order.validTo - 60 * 30);
        uint64 quoteId = uint64(0);
        CowSwapOnchainOrder.OnchainSignature
            memory signature = CowSwapOnchainOrder.OnchainSignature(
                CowSwapOnchainOrder.OnchainSigningScheme.Eip1271,
                abi.encodePacked(address(this))
            );
        GPv2Order.Data memory modified_order_of_ethflow_contract = order;
        modified_order_of_ethflow_contract.validTo = type(uint32).max;
        // Todo: Acutally, we wanna check vm.expectEmit(true, false, false, true, address(ethflow));
        // Generally, I really don't like the log testing with foundry
        vm.expectEmit(true, false, false, false, address(ethflow));
        emit CowSwapOnchainOrder.OrderPlacement(
            address(this),
            modified_order_of_ethflow_contract,
            signature,
            abi.encodePacked(quoteId)
        );
        ethflow.createOrder{value: order.sellAmount}(order, quoteId);
    }

    function testOrderCreationNotPossibleWithInvalidValidTo() public {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        vm.warp(order.validTo + 1);
        uint64 quoteId = uint64(0);
        vm.expectRevert("order no longer valid");
        ethflow.createOrder{value: order.sellAmount}(order, quoteId);
    }

    function testOrderCreationRevertsForNonSellOrders() public {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        vm.warp(order.validTo - 60 * 30);
        uint64 quoteId = uint64(0);
        order.kind = GPv2Order.KIND_BUY;
        vm.expectRevert("only sell orders are allowed");
        ethflow.createOrder{value: order.sellAmount}(order, quoteId);
    }

    function testOrderCreationRevertsIfSellamountIsNotCorrect() public {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        vm.warp(order.validTo - 60 * 30);
        uint64 quoteId = uint64(0);
        vm.expectRevert("not sufficient ether supplied for order");
        ethflow.createOrder{value: order.sellAmount + 1}(order, quoteId);
    }

    function testIsValidSignatureSuccessfully() public {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        vm.warp(order.validTo - 600);
        uint64 quoteId = uint64(0);
        bytes32 orderDigest = ethflow.createOrder{value: order.sellAmount}(
            order,
            quoteId
        );
        vm.warp(order.validTo - 600);
        ethflow.isValidSignature(orderDigest, "");
    }

    function testIsValidSignatureRevertsIfOrderNoLongerValid() public {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        vm.warp(order.validTo - 1);
        uint64 quoteId = uint64(0);
        bytes32 orderDigest = ethflow.createOrder{value: order.sellAmount}(
            order,
            quoteId
        );
        vm.warp(order.validTo + 1);
        vm.expectRevert("order no longer valid");
        ethflow.isValidSignature(orderDigest, "");
    }

    function testOrderRefundSuccessfully() public payable {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        vm.warp(order.validTo - 1);
        uint64 quoteId = uint64(0);
        bytes32 orderDigest = ethflow.createOrder{value: order.sellAmount}(
            order,
            quoteId
        );
        vm.warp(order.validTo + 1);
        order.validTo = type(uint32).max;
        bytes memory uid = new bytes(GPv2Order.UID_LENGTH);
        uid.packOrderUidParams(orderDigest, address(ethflow), order.validTo);
        uint256 filledAmount = 0;
        vm.mockCall(
            address(settlement),
            abi.encodeWithSelector(ISettlement.filledAmount.selector, uid),
            abi.encode(filledAmount)
        );
        // next two transactions simulate weth return + eth funding
        vm.mockCall(
            address(weth),
            order.sellAmount,
            abi.encodeWithSelector(IWETH.withdraw.selector, order.sellAmount),
            abi.encode()
        );
        vm.deal(address(ethflow), order.sellAmount);
        ethflow.orderRefund(order);
    }

    function testOrderRefundCheckThatItSendsBackETH() public payable {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        vm.warp(order.validTo - 1);
        uint64 quoteId = uint64(0);
        bytes32 orderDigest = ethflow.createOrder{value: order.sellAmount}(
            order,
            quoteId
        );
        vm.warp(order.validTo + 1);
        order.validTo = type(uint32).max;
        bytes memory uid = new bytes(GPv2Order.UID_LENGTH);
        uid.packOrderUidParams(orderDigest, address(ethflow), order.validTo);
        uint256 filledAmount = 1;
        vm.mockCall(
            address(settlement),
            abi.encodeWithSelector(ISettlement.filledAmount.selector, uid),
            abi.encode(filledAmount)
        );
        // next two transactions simulate weth return + eth funding
        vm.mockCall(
            address(weth),
            order.sellAmount,
            abi.encodeWithSelector(IWETH.withdraw.selector, order.sellAmount),
            abi.encode()
        );
        vm.deal(address(ethflow), order.sellAmount);
        uint256 balanceBefore = address(this).balance;
        ethflow.orderRefund(order);
        assertEq(
            balanceBefore + order.sellAmount - filledAmount,
            address(this).balance
        );
    }

    function testOrderRefundRevertsIfOrderIsStillValid() public payable {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        vm.warp(order.validTo - 1);
        uint64 quoteId = uint64(0);
        ethflow.createOrder{value: order.sellAmount}(order, quoteId);
        order.validTo = type(uint32).max;
        vm.expectRevert("order still valid");
        ethflow.orderRefund(order);
    }

    function testOrderRefundRevertsForSomeRandomOrder() public payable {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        vm.warp(order.validTo - 1);
        uint64 quoteId = uint64(0);
        ethflow.createOrder{value: order.sellAmount}(order, quoteId);
        order.validTo = type(uint32).max;
        order.sellAmount = 12341234;
        bytes32 orderDigest = order.hash(CowSwapEip712.domainSeparator());
        bytes memory uid = new bytes(GPv2Order.UID_LENGTH);
        uid.packOrderUidParams(orderDigest, address(ethflow), order.validTo);
        uint256 filledAmount = 0;
        vm.mockCall(
            address(settlement),
            abi.encodeWithSelector(ISettlement.filledAmount.selector, uid),
            abi.encode(filledAmount)
        );
        vm.expectRevert("Failed to send Ether");
        ethflow.orderRefund(order);
    }

    function testOrderRefundDeletesRefundedOrder() public payable {
        GPv2Order.Data memory order = helperCreateTestOrderData();
        vm.warp(order.validTo - 1);
        uint64 quoteId = uint64(0);
        bytes32 orderDigest = ethflow.createOrder{value: order.sellAmount}(
            order,
            quoteId
        );
        vm.warp(order.validTo + 1);
        order.validTo = type(uint32).max;
        bytes memory uid = new bytes(GPv2Order.UID_LENGTH);
        uid.packOrderUidParams(orderDigest, address(ethflow), order.validTo);
        uint256 filledAmount = 0;
        vm.mockCall(
            address(settlement),
            abi.encodeWithSelector(ISettlement.filledAmount.selector, uid),
            abi.encode(filledAmount)
        );
        vm.deal(address(ethflow), order.sellAmount);
        ethflow.orderRefund(order);
        assertEq(ethflow.orders(orderDigest), bytes32(0));
    }

    receive() external payable {}
}
