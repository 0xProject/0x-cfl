const fs = require("fs");
const path = require("path");
const SimpleTokenSwap = artifacts.require("SimpleTokenSwap");
const CONFIG = require("../truffle-config");

module.exports = function (deployer, network) {
  deployer
    .deploy(
      SimpleTokenSwap,
      CONFIG.networks[network].weth,
      CONFIG.networks[network].allowance_holder
    )
    .then((deployed) => {
      if (network.startsWith("forked-")) {
        // Update the forked deployed address in package.json.
        const PACKAGE_CONFIG = require("../package.json");
        PACKAGE_CONFIG.config.forked_deployed_address = deployed.address;
        fs.writeFileSync(
          path.resolve(__dirname, "../package.json"),
          JSON.stringify(PACKAGE_CONFIG, null, "    ")
        );
      }
    });
};
