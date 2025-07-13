import { ethers } from 'hardhat';
import { computeCreate2Address } from './utils/create2';

// Known CREATE2 factory addresses on various chains
const CREATE2_FACTORIES = {
  // Nick's deterministic deployment factory
  universal: '0x4e59b44847b379578588920cA78FbF26c0B4956C',
  // Add custom factory addresses per chain if needed
};

async function main() {
  const contracts = [
    { name: 'Bridge', constructorArgs: ['0x0000000000000000000000000000000000000000', 25] },
    { name: 'LuxVault', constructorArgs: [] },
    { name: 'WLUX', constructorArgs: [] },
    { name: 'UniswapV2Factory', constructorArgs: ['0x0000000000000000000000000000000000000000'] },
    { name: 'CREATE2Factory', constructorArgs: [] },
  ];

  console.log('Computing CREATE2 addresses for all chains...\n');

  for (const contract of contracts) {
    console.log(`${contract.name}:`);
    
    // Get contract factory
    const factory = await ethers.getContractFactory(contract.name);
    
    // Get init code with constructor args
    const initCode = factory.getDeployTransaction(...contract.constructorArgs).data!;
    
    // Compute salt (same for all chains for consistency)
    const salt = ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(['string'], [`LUX_${contract.name.toUpperCase()}_V1`])
    );
    
    // Compute address for universal factory
    const create2Address = computeCreate2Address(
      CREATE2_FACTORIES.universal,
      salt,
      initCode
    );
    
    console.log(`  Salt: ${salt}`);
    console.log(`  Address: ${create2Address}`);
    console.log(`  (Same on all chains with factory at ${CREATE2_FACTORIES.universal})\n`);
  }
}

// Helper function to compute CREATE2 address
export function computeCreate2Address(
  factoryAddress: string,
  salt: string,
  initCode: string
): string {
  const initCodeHash = ethers.utils.keccak256(initCode);
  
  return ethers.utils.getAddress(
    '0x' +
      ethers.utils
        .keccak256(
          ethers.utils.concat([
            '0xff',
            factoryAddress,
            salt,
            initCodeHash,
          ])
        )
        .slice(-40)
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });