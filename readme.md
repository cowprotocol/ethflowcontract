# ETH flow contracts

Smart contracts that enable native ETH sell orders on CoW Swap.

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

The tag `master-artifacts` is kept up to date with the latest working version of current master and provides up-to-date artifacts.

To manually generate the build artifacts, run:

```sh
forge build -o artifacts
```

### Deploy

The ETH flow contract has a dedicated deployment script. To simulate a deployment, run:

```sh
forge script script/Deploy.sol --rpc-url "$RPC_URL" -vvvv
```

You can find a list of supported RPC URLs in `foundry.toml` under `[rpc_endpoints]`.

To broadcast the deployment onchain you must also add the private key of the deployer and the broadcast flag: `--private-key "$PK" --broadcast`.

You can verify a contract you deployed with the deployment script on the block explorer of the current chain with:

```sh
export ETHERSCAN_API_KEY=<your Etherscan API key> # Only needed if the default chain explorer is Etherscan
forge script script/Deploy.sol --rpc-url "$RPC_URL" ---vvvv
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
