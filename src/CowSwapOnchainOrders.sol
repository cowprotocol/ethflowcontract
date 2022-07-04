// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "./vendored/GPv2Order.sol";
import "./libraries/CowSwapEip712.sol";

contract CowSwapOnchainOrders {
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    /// @dev The domain separator for the CowSwap settlement contract.
    bytes32 public immutable cowSwapDomainSeparator;

    constructor() {
        cowSwapDomainSeparator = CowSwapEip712.domainSeparator();
    }

    enum OnchainSigningScheme {
        Eip1271,
        PreSign
    }

    struct OnchainSignature {
        OnchainSigningScheme scheme;
        bytes data;
    }

    event OrderPlacement(
        address indexed owner,
        GPv2Order.Data order,
        OnchainSignature signature,
        bytes data
    );

    function placeOrder(
        GPv2Order.Data memory order,
        OnchainSignature memory signature,
        bytes memory data
    ) public returns (bytes memory orderUid) {
        emit OrderPlacement(msg.sender, order, signature, data);
        orderUid.packOrderUidParams(
            order.hash(cowSwapDomainSeparator),
            msg.sender,
            order.validTo
        );
    }
}
