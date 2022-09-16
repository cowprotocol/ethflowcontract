// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "../../../src/interfaces/ICoWSwapSettlement.sol";
import "../../../src/vendored/IERC20.sol";

interface ICoWSwapSettlementExtended is ICoWSwapSettlement {
    // https://github.com/cowprotocol/contracts/blob/v1.0.0/src/contracts/libraries/GPv2Trade.sol#L16-L28
    struct TradeData {
        uint256 sellTokenIndex;
        uint256 buyTokenIndex;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        uint256 flags;
        uint256 executedAmount;
        bytes signature;
    }

    // https://github.com/cowprotocol/contracts/blob/v1.0.0/src/contracts/libraries/GPv2Interaction.sol#L9-L13
    struct InteractionData {
        address target;
        uint256 value;
        bytes callData;
    }

    function authenticator() external returns (address);

    function domainSeparator() external returns (bytes32);

    function settle(
        IERC20[] calldata tokens,
        uint256[] calldata clearingPrices,
        TradeData[] calldata trades,
        InteractionData[][3] calldata interactions
    ) external;
}
