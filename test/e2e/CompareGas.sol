// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

// solhint-disable reason-string
// solhint-disable not-rely-on-time
// solhint-disable avoid-low-level-calls

import "openzeppelin-contracts/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol" as OpenZeppelin;
import "./DeploymentSetUp.sol";
import "../FillWithSameByte.sol";
import "../../src/CoWSwapEthFlow.sol";
import "../../src/vendored/GPv2Order.sol";

contract CompareGas {
    function createOrderAndSettle(
        ICoWSwapEthFlow ethFlow,
        EthFlowOrder.Data memory order,
        uint256 ethValue,
        ICoWSwapSettlementExtended settlement,
        IERC20[] calldata tokens,
        uint256[] calldata clearingPrices,
        ICoWSwapSettlementExtended.TradeData[] calldata trades,
        ICoWSwapSettlementExtended.InteractionData[][3] memory interactions
    ) public {
        ethFlow.createOrder{value: ethValue}(order);
        settlement.settle(tokens, clearingPrices, trades, interactions);
    }
}

contract TradingWithCowSwap is DeploymentSetUp {
    using EthFlowOrder for EthFlowOrder.Data;
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    CoWSwapEthFlow public ethFlow;
    OpenZeppelin.ERC20PresetMinterPauser public cowToken;
    ICoWSwapSettlementExtended public settlement;
    IWrappedNativeToken public weth;

    function setUp() public {
        Contracts memory c = deploy();
        settlement = c.settlement;
        weth = c.weth;
        cowToken = new OpenZeppelin.ERC20PresetMinterPauser("CoW Token", "COW");
        ethFlow = new CoWSwapEthFlow(settlement, weth);
    }

    function testSingleTrade() public {
        // Sell 1 ETH for 15k COW (plus 0.01 ETH fees) using the internal buffer of the settlement contract.
        uint256 sellAmount = 1 ether;
        uint256 feeAmount = 0.01 ether;

        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(address(cowToken)),
            FillWithSameByte.toAddress(0x31),
            sellAmount,
            15000 ether,
            FillWithSameByte.toBytes32(0xaa), //appData
            feeAmount,
            31337, //validTo
            false, //partiallyFillable
            424242 //quoteId
        );
        assertLt(block.timestamp, order.validTo);

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = weth;
        tokens[1] = IERC20(address(cowToken));

        uint256[] memory clearingPrices = new uint256[](2);
        clearingPrices[0] = order.buyAmount;
        clearingPrices[1] = sellAmount;

        bytes memory eip1271EthFlowSignature = abi.encodePacked(ethFlow);
        ICoWSwapSettlementExtended.TradeData memory trade = deriveTrade(
            0,
            1,
            order,
            sellAmount,
            eip1271EthFlowSignature
        );
        ICoWSwapSettlementExtended.TradeData[]
            memory trades = new ICoWSwapSettlementExtended.TradeData[](1);
        trades[0] = trade;

        ICoWSwapSettlementExtended.InteractionData
            memory wrap = ICoWSwapSettlementExtended.InteractionData(
                address(ethFlow),
                0,
                abi.encodeCall(ICoWSwapEthFlow.wrap, sellAmount + feeAmount)
            );
        ICoWSwapSettlementExtended.InteractionData[]
            memory preInteractions = new ICoWSwapSettlementExtended.InteractionData[](
                1
            );
        preInteractions[0] = wrap;
        ICoWSwapSettlementExtended.InteractionData[][3] memory interactions = [
            preInteractions,
            new ICoWSwapSettlementExtended.InteractionData[](0),
            new ICoWSwapSettlementExtended.InteractionData[](0)
        ];

        CompareGas gasComparingUser = new CompareGas();
        // Switching from a zero storage slot to a nonzero one is more expensive. This happens only in the first trade.
        // We wrap some eth to remove this bias.
        vm.deal(address(ethFlow), 1);
        vm.prank(address(ethFlow));
        weth.deposit{value: 1}();
        // Fill buffer with enough funds in buffer to settle the order
        cowToken.mint(address(settlement), order.buyAmount);
        vm.deal(address(gasComparingUser), sellAmount + feeAmount);
        gasComparingUser.createOrderAndSettle(
            ethFlow,
            order,
            order.sellAmount + order.feeAmount,
            settlement,
            tokens,
            clearingPrices,
            trades,
            interactions
        );
    }

    function deriveTrade(
        uint256 sellTokenIndex,
        uint256 buyTokenIndex,
        EthFlowOrder.Data memory order,
        uint256 executedAmount,
        bytes memory signature
    ) internal pure returns (ICoWSwapSettlementExtended.TradeData memory) {
        return
            ICoWSwapSettlementExtended.TradeData(
                sellTokenIndex,
                buyTokenIndex,
                order.receiver,
                order.sellAmount,
                order.buyAmount,
                type(uint32).max, // validTo;
                order.appData,
                order.feeAmount,
                packFlags(order.partiallyFillable),
                executedAmount,
                signature
            );
    }

    function packFlags(bool partiallyFillable) internal pure returns (uint256) {
        // For information on flag encoding, see:
        // https://github.com/cowprotocol/contracts/blob/v1.0.0/src/contracts/libraries/GPv2Trade.sol#L70-L93
        uint256 sellOrderFlag = 0;
        uint256 fillOrKillFlag = (partiallyFillable ? 1 : 0) << 1;
        uint256 internalSellTokenBalanceFlag = 0 << 2;
        uint256 internalBuyTokenBalanceFlag = 0 << 4;
        uint256 eip1271SignatureFlag = 2 << 5;
        return
            sellOrderFlag |
            fillOrKillFlag |
            internalSellTokenBalanceFlag |
            internalBuyTokenBalanceFlag |
            eip1271SignatureFlag;
    }
}
