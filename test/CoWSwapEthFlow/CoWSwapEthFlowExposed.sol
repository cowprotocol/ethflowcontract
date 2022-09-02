// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "../../src/CoWSwapEthFlow.sol";
import "../../src/interfaces/ICoWSwapSettlement.sol";

/// @dev Wrapper that exposes internal funcions of CoWSwapEthFlow.
contract CoWSwapEthFlowExposed is CoWSwapEthFlow {
    constructor(
        ICoWSwapSettlement settlementContractAddress,
        IWrappedNativeToken wrappedNativeToken
    )
        CoWSwapEthFlow(settlementContractAddress, wrappedNativeToken)
    // solhint-disable-next-line no-empty-blocks
    {

    }

    function cowSwapDomainSeparatorPublic() public view returns (bytes32) {
        return cowSwapDomainSeparator;
    }
}
