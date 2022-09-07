// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol" as OpenZeppelin;
import "./ValidatedAddress.sol";
import "../src/CoWSwapEthFlow.sol";
import "../src/vendored/GPv2Order.sol";
import "../test/FillWithSameByte.sol";
import "../test/e2e/DeploymentSetUp.sol";
import "../test/e2e/ICoWSwapSettlementExtended.sol";

/// @title Gas benchmark
/// @author CoW Swap Developers.
contract GasBenchmark is Script {
    CoWSwapEthFlow public ethFlow;
    OpenZeppelin.ERC20PresetMinterPauser public cowToken;
    ICoWSwapSettlementExtended public settlement;
    IWrappedNativeToken public weth;

    function run() external {
        weth = IWrappedNativeToken(ValidatedAddress.wrappedNativeToken());
        settlement = ICoWSwapSettlementExtended(
            address(ValidatedAddress.cowSwapSettlement())
        );

        vm.broadcast(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        ethFlow = new CoWSwapEthFlow(settlement, weth);
        vm.broadcast(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        cowToken = new OpenZeppelin.ERC20PresetMinterPauser("CoW Token", "COW");

        address user = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Owns eth
        uint256 sellAmount = 1 ether;
        uint256 feeAmount = 0.01 ether;

        EthFlowOrder.Data memory order = EthFlowOrder.Data(
            IERC20(address(cowToken)),
            FillWithSameByte.toAddress(0x31),
            sellAmount,
            15000 ether,
            FillWithSameByte.toBytes32(0xaa), //appData
            feeAmount,
            uint32(block.timestamp + 31337), //validTo
            false, //partiallyFillable
            424242 //quoteId
        );
        IERC20[] memory tokens = new IERC20[](2);
        uint256[] memory clearingPrices = new uint256[](2);
        ICoWSwapSettlementExtended.TradeData[] memory trades;
        ICoWSwapSettlementExtended.InteractionData[][3] memory interactions;

        // Avoid stack too deep
        {
            // Create an order and wrap just to make the weth and eth balances nonzero.
            //getEth(address(1337), sellAmount + feeAmount);

            vm.broadcast(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
            ethFlow.createOrder{value: sellAmount + feeAmount}(order);
            // Sent from an actual mainnet solver
            //vm.broadcast(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
            //ethFlow.wrap(1); // Any nonzero amount works for this purpose.

            // Sligtly change the order to create another one.
            order.appData = FillWithSameByte.toBytes32(0xbb);

            // Fill buffer with enough funds in buffer to settle the order
            vm.broadcast(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
            cowToken.mint(address(settlement), order.buyAmount);
            // Give user enough funds to create the order
            //getEth(user, sellAmount + feeAmount);

            // Prepare settlement
            uint256 wethIndex = 0;
            uint256 cowIndex = 1;
            tokens[wethIndex] = weth;
            tokens[cowIndex] = IERC20(address(cowToken));

            clearingPrices[wethIndex] = order.buyAmount;
            clearingPrices[cowIndex] = sellAmount;

            bytes memory eip1271EthFlowSignature = abi.encodePacked(ethFlow);
            ICoWSwapSettlementExtended.TradeData memory trade = deriveTrade(
                wethIndex,
                cowIndex,
                order,
                sellAmount,
                eip1271EthFlowSignature
            );
            trades = new ICoWSwapSettlementExtended.TradeData[](1);
            trades[0] = trade;

            interactions = wrapInteractions(sellAmount + feeAmount);
        }

        vm.broadcast(user);
        ethFlow.createOrder{value: sellAmount + feeAmount}(order);

        // Sent from an actual mainnet solver
        vm.broadcast(0x976EA74026E726554dB657fA54763abd0C3a0aa9);
        settlement.settle(tokens, clearingPrices, trades, interactions);
    }

    function wrapInteractions(uint256 amount)
        internal
        view
        returns (
            ICoWSwapSettlementExtended.InteractionData[][3] memory interactions
        )
    {
        ICoWSwapSettlementExtended.InteractionData
            memory wrap = ICoWSwapSettlementExtended.InteractionData(
                address(ethFlow),
                0,
                abi.encodeCall(ICoWSwapEthFlow.wrap, amount)
            );
        ICoWSwapSettlementExtended.InteractionData[]
            memory preInteractions = new ICoWSwapSettlementExtended.InteractionData[](
                1
            );
        preInteractions[0] = wrap;
        interactions = [
            preInteractions,
            new ICoWSwapSettlementExtended.InteractionData[](0),
            new ICoWSwapSettlementExtended.InteractionData[](0)
        ];
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
