// 06_v2router02.ts

import { Deploy } from '../utils/deploy'

export default Deploy('UniswapV2Router02', {dependencies: ['WLUX', 'UniswapV2Factory']}, async({ getChainId, deploy, deps }) => {
  const { WLUX, UniswapV2Factory } = deps
  const chainId = await getChainId()

  await deploy(
    [UniswapV2Factory.address, WLUX.address],
    // ['SafeMath', 'UniswapV2Library', 'TransferHelper']
  )
})
