// 09_dao.ts

import { Deploy } from '@zoolabs/contracts/utils/deploy'

export default Deploy('DAO', {
    proxy: { kind: 'uups' }
  },
  async({ ethers, getChainId, deploy, deps, signers }) => {
    await deploy()
  }
)
