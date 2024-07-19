import { setupTestFactory, requireDependencies } from './utils'

const { expect } = requireDependencies()
const setupTest = setupTestFactory(['LuxFarm'])

describe('LuxFarm', async () => {
  it('exists', async () => {
    const {
      tokens: { LuxFarm: token },
    } = await setupTest()
    expect(token).not.to.be.null
  })
})
