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

## Building a Cannon Package for Deployment

This project uses [Cannon](https://usecannon.com/) to generate a deployable artifact for the contracts in this repository. The deployment on live networks does not occur on this repository.

To learn more or browse artifacts for the actual deployed contracts, see [`cowprotocol/deployments` repository](https://github.com/cowprotocol/deployments) or [`cow-omnibus` on Cannon Explorer](https://usecannon.com/packages/cow-omnibus).

### Building the Cannon Package

To build a new Cannon package for the GPv2 Settlement contracts:

```sh
yarn build:cannon
```

This will:
- Recompile the Solidity contracts as needed
- Generate a deployment manifest including the solidity input json, default settings, ABIs, as well as predicted deployment addresses.
- Store the deployment artifacts in the `cannon/` directory

### Publishing the Cannon Package

When the contracts should be released to staging or production:

1. Double check that the `version` field in `cannonfile.toml` is as expected, and modify as necessary.

2. Follow instructions in [Building the Cannon Package](#Building the Cannon Package) above to ensure the artifacts are up to date.

3. Publish the cannon package using an EOA that has permission on the `cow-settlement` package. You will also need 0.0025 ETH + gas on Optimism Mainnet.

To publish, execute the publish command:

```
yarn cannon:publish
```

Where `<version>` is the version recorded in the `cannonfile.toml` from earlier, and `13370` is the anvil network created by cannon and used to prepare the packages before publishing. 

You will be prompted for the publishing network (select "Optimism") and for the private key of the account to use to publish.

4. Ensure that you have changes for git in your `cannon/` directory. If not, you may need to run the `cannon:record` command:

```
yarn cannon:record 
```

5. Bump the patch version of the package as specified in `cannonfile.toml`. This version should be bumped *after* the publish is complete.

Commit all the changes to a PR. A CI job will ensure consistency between the published package and repository files.

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
