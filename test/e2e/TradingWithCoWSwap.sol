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

contract TradingWithCowSwap is DeploymentSetUp {
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
        address user = FillWithSameByte.toAddress(0x42);
        uint256 sellAmount = 1 ether;
        uint256 buyAmount = 15000 ether;
        uint256 feeAmount = 0.01 ether;

        // Fill buffer with enough funds in buffer to settle the order
        cowToken.mint(address(settlement), buyAmount + feeAmount);
        // Give user enough funds to create the order
        vm.deal(user, sellAmount + feeAmount);

        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(address(cowToken)),
            FillWithSameByte.toAddress(0x31),
            sellAmount,
            buyAmount,
            FillWithSameByte.toBytes32(0xaa), //appData
            feeAmount,
            31337, //validTo
            false, //partiallyFillable
            424242 //quoteId
        );
        assertLt(block.timestamp, order.validTo);

        vm.prank(user);
        ethFlow.createOrder{value: sellAmount + feeAmount}(order);
        assertEq(address(ethFlow).balance, sellAmount + feeAmount);

        IERC20[] memory tokens = new IERC20[](2);
        uint256 wethIndex = 0;
        uint256 cowIndex = 1;
        tokens[wethIndex] = weth;
        tokens[cowIndex] = IERC20(address(cowToken));

        uint256[] memory clearingPrices = new uint256[](2);
        clearingPrices[wethIndex] = buyAmount;
        clearingPrices[cowIndex] = sellAmount;

        bytes memory eip1271EthFlowSignature = abi.encodePacked(ethFlow);
        ICoWSwapSettlementExtended.TradeData memory trade = deriveTrade(
            wethIndex,
            cowIndex,
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

        settlement.settle(tokens, clearingPrices, trades, interactions);
        assertEq(address(ethFlow).balance, 0);
        assertEq(cowToken.balanceOf(order.receiver), order.buyAmount);
    }

    function testPartiallyFillable() public {
        // Sell 100 ETH for 2M COW (plus 1 ETH fees) in a partially fillable order matching multiple times against the
        // internal buffer of the settlement contract.
        // When the order is 80% filled, delete it.
        address user = FillWithSameByte.toAddress(0x42);
        uint256 sellAmount = 100 ether;
        uint256 buyAmount = 2000000 ether;
        uint256 feeAmount = 1 ether;

        // Fill buffer with enough funds in buffer to settle 80% the order
        cowToken.mint(address(settlement), (buyAmount * 8) / 10);
        // Give user enough funds to create the order
        vm.deal(user, sellAmount + feeAmount);

        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(address(cowToken)),
            FillWithSameByte.toAddress(0x31),
            sellAmount,
            buyAmount,
            FillWithSameByte.toBytes32(0xaa), //appData
            feeAmount,
            31337, //validTo
            true, //partiallyFillable
            424242 //quoteId
        );
        assertLt(block.timestamp, order.validTo);

        vm.prank(user);
        ethFlow.createOrder{value: sellAmount + feeAmount}(order);

        // Wrap more than enough ETH to settle everything in advance
        uint256 wrapAmount = ((sellAmount + feeAmount) * 85) / 100;
        ICoWSwapSettlementExtended.InteractionData
            memory wrap = ICoWSwapSettlementExtended.InteractionData(
                address(ethFlow),
                0,
                abi.encodeCall(ICoWSwapEthFlow.wrap, wrapAmount)
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
        assertEq(address(ethFlow).balance, sellAmount + feeAmount);
        assertEq(weth.balanceOf(address(ethFlow)), 0);
        settlement.settle(
            new IERC20[](0),
            new uint256[](0),
            new ICoWSwapSettlementExtended.TradeData[](0),
            interactions
        );
        assertEq(address(ethFlow).balance, sellAmount + feeAmount - wrapAmount);
        assertEq(weth.balanceOf(address(ethFlow)), wrapAmount);

        uint256[5] memory filledAmounts = [
            uint256(10 ether),
            5 ether - 1,
            25 ether - 2,
            10 ether + 3,
            30 ether
        ];
        for (uint256 i = 0; i < filledAmounts.length; i++) {
            uint256 filledAmount = filledAmounts[i];

            IERC20[] memory tokens = new IERC20[](2);
            tokens[0] = weth;
            tokens[1] = IERC20(address(cowToken));

            uint256[] memory clearingPrices = new uint256[](2);
            clearingPrices[0] = buyAmount;
            clearingPrices[1] = sellAmount;

            bytes memory eip1271EthFlowSignature = abi.encodePacked(ethFlow);

            ICoWSwapSettlementExtended.TradeData memory trade = deriveTrade(
                0,
                1,
                order,
                filledAmount,
                eip1271EthFlowSignature
            );
            ICoWSwapSettlementExtended.TradeData[]
                memory trades = new ICoWSwapSettlementExtended.TradeData[](1);
            trades[0] = trade;

            // Noop interactions
            ICoWSwapSettlementExtended.InteractionData[][3]
                memory interactions = [
                    new ICoWSwapSettlementExtended.InteractionData[](0),
                    new ICoWSwapSettlementExtended.InteractionData[](0),
                    new ICoWSwapSettlementExtended.InteractionData[](0)
                ];

            uint256 ethFlowBalanceBefore = weth.balanceOf(address(ethFlow));
            settlement.settle(tokens, clearingPrices, trades, interactions);
            assertGt(
                ethFlowBalanceBefore - weth.balanceOf(address(ethFlow)),
                filledAmount
            );
        }

        assertEq(
            cowToken.balanceOf(order.receiver),
            (order.buyAmount * 8) / 10
        );
        // Note: because of rounding some dust is left from the settlement.
        assertGt(
            weth.balanceOf(address(ethFlow)),
            ((sellAmount + feeAmount) * 5) / 100
        );
        assertEq(
            address(ethFlow).balance,
            ((sellAmount + feeAmount) * 15) / 100
        );

        // Delete what remains of the order
        vm.prank(user);
        ethFlow.deleteOrder(order);
        uint256 returnedFeeAmount = 0.2 ether;
        assertEq(user.balance, 20 ether + returnedFeeAmount);
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
