pragma solidity >=0.6.0;

interface ISettlement {
    function filledAmount(bytes calldata orderUid) external returns (uint256);

    function setPreSignature(bytes calldata orderUid, bool signed) external;
}
