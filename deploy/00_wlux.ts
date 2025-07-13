// 00_wlux.ts

import { Deploy } from '../utils/deploy'

export default Deploy('WLUX', {}, async({ deploy, deployments, hre }) => {
  // Check if WLUX is already deployed at the known address
  const WLUX_ADDRESS = '0x5FbDB2315678afecb367f032d93F642f64180aa3';
  
  try {
    // Try to get existing deployment
    const existing = await deployments.get('WLUX');
    console.log('WLUX already in deployments at:', existing.address);
    return;
  } catch (e) {
    // If not in deployments, save the existing deployment
    const artifact = await deployments.getArtifact('WLUX');
    await deployments.save('WLUX', {
      address: WLUX_ADDRESS,
      abi: artifact.abi,
    });
    console.log('WLUX deployment saved at:', WLUX_ADDRESS);
  }
})