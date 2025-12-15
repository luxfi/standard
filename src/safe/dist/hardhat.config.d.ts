import "@nomicfoundation/hardhat-toolbox";
import type { HardhatUserConfig } from "hardhat/types";
import "hardhat-deploy";
import "./src/tasks/local_verify";
import "./src/tasks/deploy_contracts";
import "./src/tasks/show_codesize";
declare const userConfig: HardhatUserConfig;
export default userConfig;
