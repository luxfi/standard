import { Deploy } from '@luxfi/standard/utils/deploy'

export default Deploy('Multicall2', {}, async ({ getNamedAccounts, hre, deploy, deployments, deps }) => {
  await deploy()
})
