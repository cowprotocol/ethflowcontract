// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "../../src/mixins/CoWSwapOnchainOrders.sol";

/// @dev Wrapper that exposes internal funcions of CoWSwapOnchainOrders.
contract CoWSwapOnchainOrdersExposed is CoWSwapOnchainOrders {
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    function cowSwapDomainSeparatorPublic() public view returns (bytes32) {
        return cowSwapDomainSeparator;
    }

    /// @param settlementContractAddress The address of CoW Swap's settlement contract on the chain where this contract
    /// is deployed.
    constructor(address settlementContractAddress)
        CoWSwapOnchainOrders(settlementContractAddress)
    // solhint-disable-next-line no-empty-blocks
    {

    }

    function broadcastOrderPublic(
        address sender,
        GPv2Order.Data memory order,
        OnchainSignature memory signature,
        bytes memory data
    ) public returns (bytes memory) {
        return broadcastOrder(sender, order, signature, data);
    }
}
