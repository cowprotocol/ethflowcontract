// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

import "./libraries/CowSwapOnchainOrder.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/ISettlement.sol";
import "./vendored/ERC1271.sol";
import "forge-std/console.sol";

contract CoWSwapETHFlow is ERC1271 {
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    ISettlement public immutable settlement;
    IWETH public weth;
    // bytes32 used like that:
    //uint32 validTo + address of owner + 64 unused bytes.
    mapping(bytes32 => bytes32) public orders;

    constructor(
        IWETH _weth,
        address allowance_manager,
        ISettlement _settlement
    ) {
        weth = _weth;
        settlement = _settlement;
        weth.approve(allowance_manager, type(uint256).max);
    }

    function createOrder(GPv2Order.Data memory order, uint64 quoteId)
        external
        payable
        returns (bytes32 orderDigest)
    {
        uint32 validTo = order.validTo;
        require(validTo > block.timestamp, "order no longer valid");
        require(
            order.kind == GPv2Order.KIND_SELL,
            "only sell orders are allowed"
        );
        require(
            msg.value == order.sellAmount,
            "not sufficient ether supplied for order"
        );

        order.validTo = type(uint32).max;
        CowSwapOnchainOrder.OnchainSignature
            memory signature = CowSwapOnchainOrder.OnchainSignature(
                CowSwapOnchainOrder.OnchainSigningScheme.Eip1271,
                abi.encodePacked(address(this))
            );

        bytes memory data = abi.encodePacked(validTo,quoteId);
        orderDigest = CowSwapOnchainOrder.broadcastOrder(
            order,
            signature,
            data
        );
        bytes32 validToAndUser = orders[orderDigest];
        require(validToAndUser == bytes32(0), "order already existing");
        orders[orderDigest] = bytes32(abi.encodePacked(validTo, msg.sender));
        weth.deposit{value: msg.value}();
    }

    function isValidSignature(bytes32 _hash, bytes calldata _signature)
        external
        view
        override
        returns (bytes4)
    {
        uint64 validTo = extractValidTo(orders[_hash]);
        require(validTo > block.timestamp, "order no longer valid");
        return MAGICVALUE;
    }

    function orderRefund(GPv2Order.Data calldata order) external payable {
        bytes32 orderDigest = order.hash(CowSwapEip712.domainSeparator());
        bytes32 validToAndUserInfo = orders[orderDigest];
        uint32 validTo = extractValidTo(validToAndUserInfo);
        require(validTo < block.timestamp, "order still valid");
        bytes memory uid = new bytes(GPv2Order.UID_LENGTH);
        uid.packOrderUidParams(orderDigest, address(this), order.validTo);
        uint256 refundAmount = order.sellAmount - settlement.filledAmount(uid);
        address payable user = extractUser(validToAndUserInfo);
        orders[orderDigest] = bytes32(0);
        (bool sent, ) = user.call{value: refundAmount}("");
        require(sent, "Failed to send Ether");
    }

    function extractValidTo(bytes32 validToAndUserInfo)
        internal
        pure
        returns (uint32 validTo)
    {
        validTo = uint32(bytes4(validToAndUserInfo));
    }

    function extractUser(bytes32 validToAndUserInfo)
        internal
        pure
        returns (address payable user)
    {
        bytes memory b = abi.encode(validToAndUserInfo);
        assembly {
            user := mload(add(b, 24))
        }
    }
}
