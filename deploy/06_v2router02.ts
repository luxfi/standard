// 06_v2router02.ts

import { Deploy } from '@zoolabs/contracts/utils/deploy'

export default Deploy('UniswapV2Router02', {dependencies: ['WETH', 'UniswapV2Factory']}, async({ getChainId, deploy, deps }) => {
  const { WETH, UniswapV2Factory } = deps
  const chainId = await getChainId()

  await deploy(
    [UniswapV2Factory.address, WETH.address],
    // ['SafeMath', 'UniswapV2Library', 'TransferHelper']
  )
})
