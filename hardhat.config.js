require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.22",
  networks: {
    hardhat: {
      gas: 100000000,
      blockGasLimit: 100000000,
      allowUnlimitedContractSize: true,
    },
  },
};
