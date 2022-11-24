// This file is used to generate build artifacts that conform to Hardhat's format.
module.exports = {
  paths: {
    root: "../../",
    artifacts: "hardhat-artifacts/",
    cache: "cache/hardhat/",
    sources: "src/",
  },
  solidity: {
    // Settings copied from foundry.toml
    version: "0.8.16",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000000,
      },
    },
  },
};
