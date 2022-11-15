import "@nomiclabs/hardhat-waffle";
import "hardhat-deploy";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "@tenderly/hardhat-tenderly";

const DEFAULT_MNEMONIC =
  "candy maple cake sugar pudding cream honey rich smooth crumble sweet treat";

export default {
  paths: {
    artifacts: "build/artifacts",
    cache: "build/cache",
    deploy: "src/deploy",
    sources: "src/",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000000,
          },
        },
      },
    ],
  },
};
