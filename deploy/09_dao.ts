// 09_dao.ts

import { Deploy } from '../utils/deploy'

export default Deploy('DAO', {
    proxy: { kind: 'uups' }
  },
  async({ ethers, getChainId, deploy, deps, signers }) => {
    await deploy()
  }
)
