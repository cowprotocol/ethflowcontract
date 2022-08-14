// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "./vendored/GPv2Order.sol";
import "./libraries/CowSwapEip712.sol";
import "./libraries/CowSwapOnchainOrder.sol";
import "./interfaces/ISettlement.sol";

contract CowSwapOnchainOrderBroadcaster {
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    ISettlement public immutable settlement;
    address public this_contract_address;

    modifier onlyDelegateCall() {
        require(
            address(this) != this_contract_address,
            "should only be called via delegatecall"
        );
        _;
    }

    constructor(ISettlement _settlement) {
        settlement = _settlement;
        this_contract_address = address(this);
    }

    event OrderPlacement(
        address indexed owner,
        GPv2Order.Data order,
        CowSwapOnchainOrder.OnchainSignature signature,
        bytes data
    );

    function broadcastOrder(
        GPv2Order.Data memory order,
        CowSwapOnchainOrder.OnchainSignature memory signature,
        bytes memory data
    ) public returns (bytes32) {
        return CowSwapOnchainOrder.broadcastOrder(order, signature, data);
    }

    function presignOrder(
        GPv2Order.Data memory order,
        CowSwapOnchainOrder.OnchainSignature memory signature,
        bytes memory data
    ) external onlyDelegateCall returns (bytes32 orderDigest) {
        orderDigest = broadcastOrder(order, signature, data);
        bytes memory uid;
        uid.packOrderUidParams(orderDigest, msg.sender, order.validTo);
        settlement.setPreSignature(uid, true);
    }
}
