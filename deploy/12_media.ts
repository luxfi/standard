// 12_media.js

import { Deploy } from '@luxfi/standard/utils/deploy'

export default Deploy('Media', { dependencies: ['Market'] }, async ({ deploy }) => {
  await deploy(['LUXNFT', 'LUXNFT'])
})
