# ETH flow contracts

Smart contracts that enable native ETH sell orders on CoW Swap.

## Deployed contracts

The ETH-flow contract has been deployed on all networks that are supported by CoW Swap (currently Ethereum mainnet, Gnosis Chain, Arbitrum One, Base, Avalance, Optimism, BNB, Polygon and Sepolia).
There are two deployments of the ETH-flow contract for each network: one is used in the production environment and one is used in the barn (staging/testing) environment.
The bytecode and parameters are the same for all contracts in the same network.

You can find deployment details by network id in `broadcast/Deploy.sol/`.

We also release all current contract addresses together with our build artifacts.
The addresses of the ETH-flow's latest deployments can be found [here (production)](https://github.com/cowprotocol/ethflowcontract/blob/main-artifacts/networks.prod.json) and [here (barn)](https://github.com/cowprotocol/ethflowcontract/blob/main-artifacts/networks.barn.json)

You can also retrieve the deployed contract for any tagged version.
For example, for version v1.0.0 you can find the contract addresses for production [here](https://github.com/cowprotocol/ethflowcontract/blob/v1.0.0-artifacts/networks.prod.json) and for barn [here](https://github.com/cowprotocol/ethflowcontract/blob/v1.0.0-artifacts/networks.barn.json).

## Development

### Install

This project uses Foundry for development and testing.
Instructions on how to install this framework can be found [here](https://book.getfoundry.sh/getting-started/installation.html).

Other required NPM-based dev toolings can be installed using yarn.

```sh
yarn install
```

### Build

```sh
forge build
```

#### Build artifacts

Build artifacts are automatically generated for every tagged version.

A version of the code at tag `tag-name` with build artifacts included can ba found at tag `tag-name-artifacts`.
Artifacts are stored in the folder `artifacts` in the root directory.

The tag `main-artifacts` is kept up to date with the latest working version of current main and provides up-to-date artifacts.

To manually generate the build artifacts, run:

```sh
forge build -o artifacts
```

### Deploy

The ETH flow contract has a dedicated deployment script. To simulate a deployment, run:

```sh
forge script script/Deploy.sol --rpc-url "$RPC_URL" -vvvv --sender $DEPLOYER
```

You can find a list of supported RPC URLs in `foundry.toml` under `[rpc_endpoints]`.

To broadcast the deployment onchain you must also replace the `--sender` flag with the private key of the deployer and add the broadcast flag: `--private-key "$PK" --broadcast`.

_Note: For chains that don't support EIP-1559 by default, append `--legacy` flag._

You can verify a contract you deployed with the deployment script on the block explorer of the current chain with:

```sh
export ETHERSCAN_API_KEY=<your Etherscan API key> # Only needed if the default chain explorer is Etherscan
forge script script/Deploy.sol --rpc-url "$RPC_URL" -vvvv --private-key "$PK" --verify
```

### Code formatting

```sh
yarn fmt
```

### Test

```sh
forge test
```
Add an increased number of verbosity flags for debugging. For example:
```sh
forge test -vvv
```

For seeing line coverage results, run:
```
forge coverage
```
