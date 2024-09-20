import { task } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import { ethers } from "ethers";

task("invest-assets", "Checks the balance of an account on an ERC-20 token")
  // .addParam("account", "The account address")
  .addParam("contract", "The hello contract address")
  .setAction(async (taskArgs, hre) => {
    // const account: string = taskArgs.account;
    const contractAddress: string = taskArgs.contract;

    // Get the signer (default to the first account in the hardhat node)
    const [signer] = await hre.ethers.getSigners();

    // ABI of the contract
    const helloAbi = [
      "function investAssets()",
    ];

    const helloContract = new hre.ethers.Contract(contractAddress, helloAbi, signer);

    // Set a manual gas limit
    const gasLimit = 30000000; // Set the desired gas limit

    // Call the contract's investAssets function with the gas limit override
    await helloContract.investAssets({
      gasLimit: gasLimit,
    });

    console.log("All done");
  });

export { };
