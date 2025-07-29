// 09_dao.ts

import { Deploy } from '@luxfi/standard/utils/deploy'

export default Deploy('DAO', {
    proxy: { kind: 'uups' }
  },
  async({ ethers, getChainId, deploy, deps, signers }) => {
    await deploy()
  }
)
