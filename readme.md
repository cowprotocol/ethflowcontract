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
