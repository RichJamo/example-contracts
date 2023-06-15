import "@nomicfoundation/hardhat-toolbox";
import "./tasks/account";
import "./tasks/faucet";
import "./tasks/balances";
import "./tasks/verify";
import "./tasks/deploy";
import "./tasks/counter_increment";
import "./tasks/counter_show";

import { getHardhatConfigNetworks } from "@zetachain/addresses-tools/dist/networks";
import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/config";

dotenv.config();
const PRIVATE_KEYS =
  process.env.PRIVATE_KEY !== undefined ? [`0x${process.env.PRIVATE_KEY}`] : [];

const config: HardhatUserConfig = {
  networks: {
    ...getHardhatConfigNetworks(PRIVATE_KEYS),
  },
  solidity: "0.8.7",
};

export default config;
