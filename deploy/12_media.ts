// 12_media.js

import { Deploy } from '../utils/deploy'

export default Deploy('Media', { dependencies: ['Market'] }, async ({ deploy }) => {
  await deploy(['LUXNFT', 'LUXNFT'])
})
