// 12_media.js

import { Deploy } from '@luxdefi/contracts/utils/deploy'

export default Deploy('Media', { dependencies: ['Market'] }, async ({ deploy }) => {
  await deploy(['LUXNFT', 'LUXNFT'])
})
