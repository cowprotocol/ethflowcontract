// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "../src/vendored/IERC20.sol";
import "../src/vendored/GPv2Order.sol";
import "../src/CoWSwapETHFlowExternalOnchainOrdersContract.sol";
import "../src/CowSwapOnchainOrders.sol";
import "forge-std/console.sol";


contract TestCoWSwapETHFlowExternalOnchainOrdersContract is Test {
    CoWSwapETHFlowExternalOnchainOrdersContract public ethflow;
    CowSwapOnchainOrders public onchainOrderRegister;
    function setUp() public {
        onchainOrderRegister = new CowSwapOnchainOrders();
        ethflow = new CoWSwapETHFlowExternalOnchainOrdersContract(onchainOrderRegister);
    }

    function testOrderCreationGasCosts() public {
        uint32 validTo = 500000;
        // set current timestamp such that validTo is in the future 
        vm.warp(validTo-60*30);
        GPv2Order.Data memory order = GPv2Order.Data(IERC20(address(1)),IERC20(address(2)),address(1),1,1,validTo,bytes32(0),1,GPv2Order.KIND_SELL,false,bytes32(0),bytes32(0));
        uint64 quoteId = uint64(0);
        ethflow.createOrder{value:1}(order, quoteId);
    }

    function testSimpleExternalOverhead() public view {
        ethflow.fnCallingExteralOrInheritedFn();
    }
}
