const HDWalletProvider = require("@truffle/hdwallet-provider");
const { MNEMONIC, RPC_URL } = require("process").env;

module.exports = {
  /**
   * Networks define how you connect to your ethereum client and let you set the
   * defaults web3 uses to send transactions. If you don't specify one truffle
   * will spin up a development blockchain for you on port 9545 when you
   * run `develop` or `test`. You can ask a truffle command to use a specific
   * network from the command line, e.g
   *
   * $ truffle test --network <network-name>
   */

  networks: {
    development: {
      host: "localhost",
      port: 8545,
      network_id: "*",
      weth: "0x0000000000000000000000000000000000000000",
      allowance_holder: "0x0000000000000000000000000000000000000000",
    },
    "forked-mainnet": {
      host: "localhost",
      port: 7545,
      network_id: "1",
      skipDryRun: true,
      weth: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
      allowance_holder: "0x0000000000001fF3684f28c67538d4D072C22734",
    },
    mainnet: {
      provider: () => new HDWalletProvider(MNEMONIC, RPC_URL),
      network_id: "1",
      weth: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
      allowance_holder: "0x0000000000001fF3684f28c67538d4D072C22734",
    },
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.26",
    },
  },
};
