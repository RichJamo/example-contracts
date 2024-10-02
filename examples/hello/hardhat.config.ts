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

import { getHardhatConfigNetworks } from "@zetachain/networks";
import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  networks: {
    ...getHardhatConfigNetworks(),
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
