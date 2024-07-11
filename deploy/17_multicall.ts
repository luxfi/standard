import { Deploy } from '@luxdefi/contracts/utils/deploy'

export default Deploy('Multicall', {}, async ({ getNamedAccounts, hre, deploy, deployments, deps }) => {
  await deploy()
})
