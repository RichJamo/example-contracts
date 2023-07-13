import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getAddress } from "@zetachain/protocol-contracts";

const contractName = "Minter";

const main = async (args: any, hre: HardhatRuntimeEnvironment) => {
  if (hre.network.name !== "zeta_testnet") {
    throw new Error(
      '🚨 Please use the "zeta_testnet" network to deploy to ZetaChain.'
    );
  }

  const [signer] = await hre.ethers.getSigners();
  console.log(`🔑 Using account: ${signer.address}\n`);

  const SYSTEM_CONTRACT = getAddress("systemContract", hre.network.name);
  const bitcoinChainID = 18332;

  const factory = await hre.ethers.getContractFactory(contractName);
  const contract = await factory.deploy(
    "Wrapped tBTC",
    "WTBTC",
    bitcoinChainID,
    SYSTEM_CONTRACT
  );
  await contract.deployed();

  console.log(`🚀 Successfully deployed contract on ZetaChain.
📜 Contract address: ${contract.address}

🌍 Explorer: https://athens3.explorer.zetachain.com/address/${contract.address}
`);
};

task("deploy", "Deploy the contract", main);
