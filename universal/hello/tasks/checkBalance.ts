import { task } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import { ethers } from "ethers";

task("check-balance", "Checks the balance of an account on an ERC-20 token")
  .addParam("account", "The account address")
  .addParam("token", "The ERC-20 contract address")
  .setAction(async (taskArgs, hre) => {
    const account: string = taskArgs.account;
    const tokenAddress: string = taskArgs.token;

    // Get the signer (default to the first account in the hardhat node)
    const [signer] = await hre.ethers.getSigners();

    // ABI of the ERC-20 contract
    const erc20Abi = [
      "function balanceOf(address account) view returns (uint256)",
      "function decimals() view returns (uint8)",
      "function CHAIN_ID() view returns (uint256)",
      "function SYSTEM_CONTRACT_ADDRESS() view returns (address)"
    ];

    // Connect to the ERC-20 contract
    const erc20Contract = new hre.ethers.Contract(tokenAddress, erc20Abi, signer);

    // Get the balance of the account
    const balance: ethers.BigNumber = await erc20Contract.balanceOf(account);
    console.log("Balance", balance.toString());

    // Get the token decimals
    const decimals: number = await erc20Contract.decimals();
    console.log("Decimals", decimals);

    //Get the chain id
    const chainId: number = await erc20Contract.CHAIN_ID();
    console.log("Chain ID", chainId);

    //Get the system contract address
    const systemContractAddress: string = await erc20Contract.SYSTEM_CONTRACT_ADDRESS();
    console.log("System Contract Address", systemContractAddress);

    // Format the balance
    const formattedBalance: string = ethers.utils.formatUnits(balance, decimals);

    console.log(`Balance of account ${account}: ${formattedBalance}`);
  });

export { };