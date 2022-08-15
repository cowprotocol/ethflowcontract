// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "../vendored/GPv2Order.sol";
import "./CowSwapEip712.sol";

library CowSwapOnchainOrder {
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    enum OnchainSigningScheme {
        Eip1271,
        PreSign
    }

    struct OnchainSignature {
        OnchainSigningScheme scheme;
        bytes data;
    }

    event OrderPlacement(
        address indexed sender,
        GPv2Order.Data order,
        OnchainSignature signature,
        bytes data
    );

    function broadcastOrder(
        GPv2Order.Data memory order,
        OnchainSignature memory signature,
        bytes memory data
    ) internal returns (bytes32 orderDigest) {
        emit OrderPlacement(msg.sender, order, signature, data);
        orderDigest = order.hash(CowSwapEip712.domainSeparator());
    }
}
