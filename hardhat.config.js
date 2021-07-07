require("@nomiclabs/hardhat-waffle");
require("dotenv").config();
require("@tenderly/hardhat-tenderly");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-contract-sizer");
require("hardhat-gas-reporter");
require('hardhat-spdx-license-identifier');
require('hardhat-log-remover');
/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.5.17",
      },
      {
        version: "0.6.2",
      },
      {
        version: "0.4.18",
      },
      {
        version: "0.6.6",
      },
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000,
          },
        },
      },
      {
        version: "0.7.5",
      },
      {
        version: "0.7.6"      },
    ],
  },

  spdxLicenseIdentifier: {
  overwrite: true,
  runOnCompile: false,
  },

  networks: {
    hardhat: {
      forking: {
        url: process.env.polygonRPC2,
        blockNumber: 16447562,
      },
      loggingEnabled: true,
    },
    localhost: {
      url: "http://localhost:8545",
      timeout: 120000
    }
  },

  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: true,
  },

  mocha: { timeout: 9999999999 },
};
