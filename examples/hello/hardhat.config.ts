import "./tasks/deploy";
import "./tasks/deployGeneric";
import "./tasks/deployUpgradeableVault";
import "./tasks/deployStrategy";
import "./tasks/deployRevert";
import "./tasks/solana/interact";
import "@zetachain/localnet/tasks";
import "@nomicfoundation/hardhat-toolbox";
import "@zetachain/toolkit/tasks";
import "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";

import { getHardhatConfigNetworks } from "@zetachain/networks";
import { HardhatUserConfig } from "hardhat/config";

dotenv.config();

const config: HardhatUserConfig = {
  networks: {
    ...getHardhatConfigNetworks(),
    base_sepolia: {
      url: `https://base-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`, // or equivalent provider URL
      accounts: [`0x${process.env.PRIVATE_KEY}`], // Add your private key here
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.8.26",
      },
      {
        version: "0.8.7",
      },
    ],
  },
};

export default config;
