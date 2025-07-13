import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from 'hardhat';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, get, save } = deployments;
  const { deployer } = await getNamedAccounts();

  // Deploy CREATE2 Factory if not already deployed
  const create2Factory = await deploy('CREATE2Factory', {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: true, // This will use a deterministic address
  });

  console.log('CREATE2Factory deployed at:', create2Factory.address);

  // Example: Deploy Bridge contract using CREATE2
  if (create2Factory.newlyDeployed) {
    const factory = await ethers.getContractAt('CREATE2Factory', create2Factory.address);
    
    // Get DAO address for Bridge constructor
    const dao = await get('DAO');
    
    // Prepare Bridge bytecode with constructor args
    const Bridge = await ethers.getContractFactory('Bridge');
    const bridgeInitCode = Bridge.getDeployTransaction(dao.address, 25).data!;
    
    // Compute salt (could be based on chain ID for cross-chain consistency)
    const chainId = await hre.getChainId();
    const salt = ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(['string', 'uint256'], ['LUX_BRIDGE_V1', chainId])
    );
    
    // Get predicted address
    const predictedAddress = await factory.getAddress(salt, bridgeInitCode);
    console.log('Bridge will be deployed at:', predictedAddress);
    
    // Check if already deployed
    const isDeployed = await factory.isDeployed(predictedAddress);
    
    if (!isDeployed) {
      // Deploy using CREATE2
      const tx = await factory.deploy(salt, bridgeInitCode);
      const receipt = await tx.wait();
      
      console.log('Bridge deployed via CREATE2 at:', predictedAddress);
      
      // Save deployment info
      await save('Bridge', {
        address: predictedAddress,
        abi: Bridge.interface.format('json'),
        transactionHash: receipt.transactionHash,
        receipt,
        args: [dao.address, 25],
        bytecode: Bridge.bytecode,
        deployedBytecode: Bridge.deployedBytecode,
      });
    } else {
      console.log('Bridge already deployed at:', predictedAddress);
    }
  }
};

export default func;
func.tags = ['CREATE2Factory', 'CREATE2'];
func.dependencies = ['DAO'];