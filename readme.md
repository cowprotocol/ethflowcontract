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
forge script script/Deploy.sol --rpc-url "$RPC_URL" -vvvv "$ETHFLOW_OBFUSCATED_PK"
```

You can find a list of supported RPC URLs in `foundry.toml` under `[rpc_endpoints]`.

`ETHFLOW_OBFUSCATED_PK` is an obfuscated version of the private key used in the deployment, _not_ a raw public key.
The purpose of obfuscating the key is making sure the same key isn't used by accident to deploy other contracts, thereby consuming the nonce of the deployer used for deterministic addresses.
It's not a security mechanism: the key is trivially recovered from the obfuscated version.

You can verify a contract you deployed with the deployment script on the block explorer of the current chain with:

```sh
export ETHERSCAN_API_KEY=<your Etherscan API key> # Only needed for etherscan-based explorers
forge script script/Deploy.sol --rpc-url "$RPC_URL" -vvvv --verify "$ETHFLOW_OBFUSCATED_PK"
```

To broadcast the deployment onchain and verify it at the same time, append `--broadcast` to the command above.

#### Obfuscate/deobfuscate a private key

For standard deployments on a new chain, there's no need to do this because the standard deployer is already provided with an obfuscated key.

If you need to generate a new obfuscated key from an actual secret key, you can run the following command:

```sh
PK=<your private key here>
forge script script/ObfuscateKey.sol "$PK"
```

To recover the actual key from an obfuscated key, you can run the exact same command: obfuscating twice returns the original key.

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
