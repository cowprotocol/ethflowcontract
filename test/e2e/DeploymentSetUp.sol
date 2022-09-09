// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

// solhint-disable reason-string
// solhint-disable not-rely-on-time
// solhint-disable avoid-low-level-calls

import "forge-std/Test.sol";
import "./DeploymentConstants.sol";
import "./ICoWSwapSettlementExtended.sol";
import "../Constants.sol";
import "../../src/interfaces/IWrappedNativeToken.sol";

contract DeploymentSetUp is Test {
    struct Contracts {
        ICoWSwapSettlementExtended settlement;
        IWrappedNativeToken weth;
    }

    function deploy() public returns (Contracts memory) {
        ICoWSwapSettlementExtended settlement = deployCoWSwapContracts();
        IWrappedNativeToken weth = deployWrappedNativeToken();
        return Contracts(settlement, weth);
    }

    function deployWrappedNativeToken()
        internal
        returns (IWrappedNativeToken wrappedNativeToken)
    {
        wrappedNativeToken = IWrappedNativeToken(
            0xE76e76E76E76E76e76e76e76E76E76E76E76e760
        );
        // Note: WETH9 has no constructor, so most features will still be working when just copying over the deployed
        // bytecode.
        // Bytecode obtained from:
        vm.etch(address(wrappedNativeToken), DeployedBytecode.WETH9);
    }

    function deployCoWSwapContracts()
        internal
        returns (ICoWSwapSettlementExtended settlement)
    {
        address deployer = deployDeterministicDeployer();
        settlement = ICoWSwapSettlementExtended(Constants.COWSWAP_SETTLEMENT);

        require(address(settlement).code.length == 0);
        // We deploy the contract in the exact same way as the real deployment.
        (bool success, ) = deployer.call(DeterministicDeploymentTx.SETTLEMENT);
        require(success, "Settlement contract deployment failed");

        // Deterministic deployment address confirms that the deployment was successful
        require(
            address(settlement).code.length != 0,
            "Settlement contract not deployed at expected address"
        );

        // Deploy trivial authenticator that accepts any address as solver.
        // No storage needs to be set, so we just copy the deployed bytecode.
        vm.etch(
            settlement.authenticator(),
            type(TrivialAuthenticator).runtimeCode
        );
    }

    function deployDeterministicDeployer() internal returns (address) {
        // The deployment is a bit unorthodox because I don't see a way to send EOA transactions from inside a test.
        // Since the deployment transaction doesn't set any storage value, we can just directly write the bytecode at
        // the expected address.
        vm.etch(
            Constants.COWSWAP_DEPLOYER,
            DeployedBytecode.DETERMINISTIC_DEPLOYER
        );
        return Constants.COWSWAP_DEPLOYER;
    }
}

// Make sure the deployed contracts work as expected
contract TestSetup is DeploymentSetUp {
    ICoWSwapSettlementExtended public settlement;
    IWrappedNativeToken public weth;

    function setUp() public {
        Contracts memory c = deploy();
        settlement = c.settlement;
        weth = c.weth;
    }

    function testWrapUnwrap() public {
        address user = address(1337);
        vm.deal(user, 100 ether);
        vm.startPrank(user);

        weth.deposit{value: 42 ether}();
        assertEq(weth.balanceOf(user), 42 ether);

        weth.withdraw(2 ether);
        assertEq(weth.balanceOf(user), 40 ether);
        assertEq((user).balance, 60 ether);

        vm.stopPrank();
    }

    function testAuthenticator() public {
        require(
            TrivialAuthenticator(settlement.authenticator()).isSolver(
                address(0x1337)
            )
        );
    }

    function testEmptySettle() public {
        IERC20[] memory tokens;
        uint256[] memory prices;
        ICoWSwapSettlementExtended.TradeData[] memory trades;
        ICoWSwapSettlementExtended.InteractionData[][3] memory interactions;
        settlement.settle(tokens, prices, trades, interactions);
    }
}

contract TrivialAuthenticator {
    function isSolver(address) public pure returns (bool) {
        return true;
    }
}
