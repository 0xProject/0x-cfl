"use strict";
require("colors");
const fetch = require("node-fetch");
const process = require("process");
const {
  createWeb3,
  createQueryString,
  etherToWei,
  waitForTxSuccess,
  weiToEther,
} = require("./utils");

const API_QUOTE_URL = "https://api.0x.org/swap/allowance-holder/quote";
const { abi: ABI } = require("../build/contracts/SimpleTokenSwap.json");

require("yargs")
  .parserConfiguration({ "parse-numbers": false })
  .command(
    "* <deployedAddress>",
    "fill a swap WETH->DAI quote through a deployed SimpleTokenSwap contract",
    (yargs) => {
      return yargs
        .option("sellAmount", {
          alias: "a",
          type: "number",
          describe: "Amount of WETH to sell (in token units)",
          default: 0.1,
        })
        .positional("deployedAddress", {
          type: "string",
          describe: "Deployed address of the SimpleTokenSwap contract",
        });
    },
    async (argv) => {
      try {
        await run(argv);
        process.exit(0);
      } catch (err) {
        console.error(err);
        process.exit(1);
      }
    }
  ).argv;

async function run(argv) {
  const web3 = createWeb3();
  const contract = new web3.eth.Contract(ABI, argv.deployedAddress);
  const [owner] = await web3.eth.getAccounts();
  const chainId = web3.eth.getChainId();

  // Convert sellAmount from token units to wei.
  const sellAmountWei = etherToWei(argv.sellAmount);

  // Deposit some WETH into the contract. This function accepts ETH and
  // wraps it to WETH on the fly.
  console.info(
    `Depositing ${argv.sellAmount} ETH (WETH) into the contract at ${argv.deployedAddress.bold}...`
  );
  await waitForTxSuccess(
    contract.methods.depositETH().send({
      value: sellAmountWei,
      from: owner,
    })
  );

  // Get a quote from 0x Swap API to sell the WETH we just deposited into the contract.
  console.info(
    `Fetching swap quote from 0x Swap API to sell ${argv.sellAmount} WETH for DAI...`
  );
  const qs = createQueryString({
    chainId: chainId.toString(),
    sellToken: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", // WETH
    buyToken: "0x6B175474E89094C44Da98b954EedeAC495271d0F", // DAI
    sellAmount: sellAmountWei,
    taker: owner,
  });
  const quoteUrl = `${API_QUOTE_URL}?${qs}`;
  console.info(`Fetching quote ${quoteUrl.bold}...`);
  const response = await fetch(quoteUrl);
  const quote = await response.json();
  console.info(`Received a quote with price ${quote.sellAmount}`);

  // Have the contract fill the quote, selling its own WETH.
  console.info(
    `Filling the quote through the contract at ${argv.deployedAddress.bold}...`
  );

  // Define the parameters for fillQuote
  let fillQuoteParams = [
    quote.sellToken,
    quote.buyToken,
    (quote.issues &&
      quote.issues.allowance &&
      quote.issues.allowance.spender) ||
      "0x0000000000000000000000000000000000000000", // Pass spender if needed to set allowance; otherwise, pass zero address if spender is not available
    quote.transaction.to,
    quote.transaction.data,
  ];
  const receipt = await waitForTxSuccess(
    contract.methods.fillQuote(...fillQuoteParams).send({
      from: owner,
      value: quote.value,
      gasPrice: quote.gasPrice,
    })
  );
  const boughtAmount = weiToEther(
    receipt.events.BoughtTokens.returnValues.boughtAmount
  );
  console.info(
    `${"✔".bold.green} Successfully sold ${
      argv.sellAmount.toString().bold
    } WETH for ${boughtAmount.bold.green} DAI!`
  );
  // The contract now has `boughtAmount` of DAI!
}
