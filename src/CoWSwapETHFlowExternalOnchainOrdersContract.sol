// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "./CowSwapOnchainOrders.sol";

contract CoWSwapETHFlowExternalOnchainOrdersContract {
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    mapping(bytes32 => bytes) public orders;
    CowSwapOnchainOrders public cowswapOnchainOrders;

    constructor(CowSwapOnchainOrders _cowswapOnchainOrders) {
        cowswapOnchainOrders = _cowswapOnchainOrders;
    }

    function createOrder(GPv2Order.Data memory order, uint64 quoteId)
        public
        payable
    {
        uint32 validTo = order.validTo;
        require(validTo > block.timestamp, "order no longer valid");
        require(
            order.kind == GPv2Order.KIND_SELL,
            "only sell orders are allowed"
        );
        require(
            msg.value == order.sellAmount,
            "not sufficient ether supplied for order"
        );
        order.validTo = type(uint32).max;
        CowSwapOnchainOrders.OnchainSignature
            memory signature = CowSwapOnchainOrders.OnchainSignature(
                CowSwapOnchainOrders.OnchainSigningScheme.Eip1271,
                abi.encodePacked(address(this), validTo)
            );
        bytes memory data = abi.encodePacked(msg.sender, quoteId);
        bytes32 orderDigest = cowswapOnchainOrders.placeOrder(
            order,
            signature,
            data
        );

        orders[orderDigest] = abi.encodePacked(validTo, msg.sender);
        // Todo: Wrap ETH
    }

    function fnCallingExteralOrInheritedFn() public view {
        cowswapOnchainOrders.simpleTestFunction();
    }

    function isValidSignature(bytes32 orderDigest, bytes calldata signature)
        public
        view
    {
        uint32 validTo;
        bytes memory t = orders[orderDigest];
        // NOTE: Use assembly to read the verifier address from the encoded
        // signature bytes.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // owner = address(encodedSignature[0:4])
            validTo := shr(32, calldataload(t))
        }
        require(
            validTo == abi.decode(signature, (uint32)),
            "validTo not the same"
        );
        require(validTo > block.timestamp, "order no longer valid");
    }
}
