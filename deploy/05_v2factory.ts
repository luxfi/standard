// 05_v2factory.ts

import { Deploy } from '@zoolabs/contracts/utils/deploy'

export default Deploy('UniswapV2Factory', {}, async({ getNamedAccounts, hre, deploy, deployments, deps }) => {
  const { deployer, dao } = await getNamedAccounts()
  await deploy([dao])
})

// // Defining bytecode and abi from original contract on mainnet to ensure bytecode matches and it produces the same pair code hash
// import {
//   bytecode,
//   abi,
// } from "../artifacts/src/uniswapv2/UniswapV2Factory.sol/UniswapV2Factory.json"

//   await deploy("UniswapV2Factory", {
//     // contract: {
//     //   abi,
//     //   bytecode,
//     // },
//     from: deployer,
//     args: [dao],
//     log: true,
//     deterministicDeployment: false,
//   });
