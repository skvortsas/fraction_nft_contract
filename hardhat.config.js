require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.16",
  settings: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
  networks: {
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/7b83987e37a0432589ab86493143de75`,
    },
    goerli: {
      url: 'https://goerli.infura.io/v3/7b83987e37a0432589ab86493143de75',
      gasPrice: 50000000000,
    }
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: ETHERSCAN_API_KEY,
  },
};
