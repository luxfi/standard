import { Deploy } from '@luxfi/standard/utils/deploy'

export default Deploy('Multicall', {}, async ({ getNamedAccounts, hre, deploy, deployments, deps }) => {
  await deploy()
})
