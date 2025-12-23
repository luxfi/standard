type ContractJson = { abi: any; bytecode: string };
const artifacts: { [name: string]: ContractJson } = {
  UniswapV3Factory: require("../../artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json"),
  UniswapV3PoolDeployer: require("../../artifacts/contracts/UniswapV3PoolDeployer.sol/UniswapV3PoolDeployer.json"),
};

export function getContractData() {
  return artifacts;
}
