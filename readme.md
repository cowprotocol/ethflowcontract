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
