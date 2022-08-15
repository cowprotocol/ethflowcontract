# ETH flow contracts

Smart contracts that enable native ETH sell orders on CowSwap.

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

or with debugging:
```sh
forge test -vvv
```

for coverage run:
```
forge coverage
```

### Deploy:

```sh
export RPC_URL=<Your RPC endpoint>
export PRIVATE_KEY=<Your wallets private key>
```

```
forge create CoWSwapETHFlow --rpc-url=$RPC_URL --private-key=$PRIVATE_KEY --constructor-args <name> <symbol>
```

on rinkeby this means:
```
forge create CoWSwapETHFlow --rpc-url=$RPC_URL --private-key=$PRIVATE_KEY \
--constructor-args 0xc778417E063141139Fce010982780140Aa0cD5Ab 0x9008D19f58AAbD9eD0D60971565AA8510560ab41 0x2c4c28DDBdAc9C5E7055b4C863b72eA0149D8aFE  \
--etherscan-api-key=$ETHERSCAN_API_KEY \
--verify
```