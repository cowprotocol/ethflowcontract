// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "../../src/CoWSwapEthFlow.sol";

/// @dev Wrapper that exposes internal funcions of CoWSwapEthFlow.
contract CoWSwapEthFlowExposed is CoWSwapEthFlow {
    constructor(address settlementContractAddress, IERC20 weth)
        CoWSwapEthFlow(settlementContractAddress, weth)
    // solhint-disable-next-line no-empty-blocks
    {

    }

    function cowSwapDomainSeparatorPublic() public view returns (bytes32) {
        return cowSwapDomainSeparator;
    }
}
