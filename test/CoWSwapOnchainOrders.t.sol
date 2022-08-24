// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "forge-std/Test.sol";
import "./CoWSwapOnchainOrders/CoWSwapOnchainOrdersExposed.sol";
import "./Constants.sol";
import "../src/vendored/GPv2Order.sol";
import "../src/interfaces/ICoWSwapOnchainOrders.sol";

contract TestCoWSwapOnchainOrders is Test, ICoWSwapOnchainOrders {
    CoWSwapOnchainOrdersExposed internal onchainOrders;

    function setUp() public {
        onchainOrders = new CoWSwapOnchainOrdersExposed(
            Constants.COWSWAP_ADDRESS
        );
    }

    function testDomainSeparator() public {
        // Other tests generate test data based on this domain separator.
        assertEq(
            onchainOrders.cowSwapDomainSeparatorPublic(),
            Constants.COWSWAP_TEST_DOMAIN_SEPARATOR
        );
    }

    function dummyOrder() public pure returns (GPv2Order.Data memory) {
        return
            GPv2Order.Data(
                IERC20(address(0x0101010101010101010101010101010101010101)), // IERC20 sellToken
                IERC20(address(0x0202020202020202020202020202020202020202)), // IERC20 buyToken
                address(address(0x0303030303030303030303030303030303030303)), // address receiver
                42 ether, // uint256 sellAmount
                1337e16, // uint256 buyAmount
                0xffffffff, // uint32 validTo
                bytes32(0), // bytes32 appData
                1 ether, // uint256 feeAmount
                GPv2Order.KIND_SELL, // bytes32 kind
                false, // bool partiallyFillable
                GPv2Order.BALANCE_ERC20, // bytes32 sellTokenBalance
                GPv2Order.BALANCE_ERC20 // bytes32 buyTokenBalance
            );
    }

    function testReturnedOrderHash() public {
        // Note: the order data is the same used here:
        // https://github.com/cowprotocol/contracts/blob/31b86ed0a882e669a3d6e2301bb432386204ecc5/test/GPv2Order.test.ts#L35-L46
        GPv2Order.Data memory order = dummyOrder();
        // Computed by running the test "computes EIP-712 order signing hash" in the contracts repo with two changes:
        // 1. Replacing `domainSeparator` with the constant at Constants.COWSWAP_TEST_DOMAIN_SEPARATOR.
        // 2. Replacing the expect line with `console.log(await orders.hashTest(encodeOrder(order), domainSeparator));`.
        // https://github.com/cowprotocol/contracts/blob/31b86ed0a882e669a3d6e2301bb432386204ecc5/test/GPv2Order.test.ts#L31-L51
        bytes32 orderHash = 0x65e25f4dac20ef9e411ba2e6a5c6c2697ce004564ffeeb5fe8a3d9f6529974f5;

        assertEq(
            onchainOrders.broadcastOrderPublic(
                address(42),
                order,
                ICoWSwapOnchainOrders.OnchainSignature(
                    ICoWSwapOnchainOrders.OnchainSigningScheme.Eip1271,
                    hex"5ec1e7"
                ),
                hex"da7a"
            ),
            orderHash
        );
    }

    function testEmitsEvent() public {
        GPv2Order.Data memory order = dummyOrder();

        address sender = address(42);
        ICoWSwapOnchainOrders.OnchainSignature
            memory signature = ICoWSwapOnchainOrders.OnchainSignature(
                ICoWSwapOnchainOrders.OnchainSigningScheme.Eip1271,
                hex"5ec1e7"
            );
        bytes memory data = hex"da7a";

        vm.expectEmit(true, true, true, true, address(onchainOrders));
        emit ICoWSwapOnchainOrders.OrderPlacement(
            sender,
            order,
            signature,
            data
        );
        onchainOrders.broadcastOrderPublic(sender, order, signature, data);
    }
}
