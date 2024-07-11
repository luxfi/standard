import { setupTestFactory, requireDependencies } from './utils'
import { Signer } from '@ethersproject/abstract-signer'
import { ZOO } from '../types'

const { expect } = requireDependencies()

const setupTest = setupTestFactory(['ZOO', 'Bridge'])

describe('ZOO', function () {
  let token: ZOO
  let signers: Signer[]

  beforeEach(async () => {
    const test = await setupTest()
    token = test.tokens.ZOO as ZOO
    signers = test.signers
  })

  it('should have correct name, symbol, decimal', async function () {
    const name = await token.name()
    const symbol = await token.symbol()
    const decimals = await token.decimals()
    expect(name.valueOf()).to.eq('ZOO')
    expect(symbol.valueOf()).to.eq('ZOO')
    expect(decimals.valueOf()).to.eq(18)
  })

  it('should add user to blacklist', async function () {
    const {
      signers,
      tokens: { ZOO },
    } = await setupTest()
    const token = ZOO

    const address = signers[1].address
    const address2 = signers[2].address

    // Add user to blacklist
    await token.blacklistAddress(address)
    expect(await token.isBlacklisted(address))

    // Only blacklist users should be blacklisted
    expect(await token.isBlacklisted(address2)).to.be.false
  })

  it('allows transfer for eligable accounts', async function () {
    const {
      signers,
      tokens: { ZOO },
    } = await setupTest()
    const token = ZOO

    const address = signers[1].address
    const address2 = signers[2].address
    const address3 = signers[3].address

    await token.mint(address, 1000)
    await token.mint(address2, 1000)
    await token.mint(address3, 1000)

    await token.connect(signers[1]).approve(address2, 1000)
    await token.connect(signers[2]).approve(address, 1000)

    const initialBalance = await token.balanceOf(address)
    await expect(token.connect(signers[2]).transferFrom(address, address2, 100)).not.to.be.reverted
  })

  it('should not allow transferFrom when blacklisted', async function () {
    const { signers, tokens } = await setupTest()
    const token = tokens['ZOO']

    const address = signers[1].address
    const address2 = signers[2].address

    await token.mint(address, 1000)
    await token.mint(address2, 1000)

    await token.connect(signers[1]).approve(address2, 1000)
    //await token.connect(signers[2]).approve(address, 1000)

    // Add user to blacklist
    await token.blacklistAddress(address)
    await expect(token.connect(signers[1]).transferFrom(address, address2, 100)).to.be.revertedWith('Address is on blacklist')
  })

  it('does not allow transfer from a blacklisted address', async function () {
    const { signers, tokens } = await setupTest()
    const token = tokens['ZOO']

    const address = signers[1].address
    const address2 = signers[2].address
    const address3 = signers[3].address

    await token.mint(address, 1000)
    await token.mint(address2, 1000)

    await token.connect(signers[1]).approve(address2, 1000)

    // Add user to blacklist
    await token.blacklistAddress(address)
    await expect(token.connect(signers[1]).transfer(address2, 100)).to.be.revertedWith('Address is on blacklist')
  })

  describe('transfer', async () => {
    it('disallows when paused', async () => {
      const {
        signers,
        tokens: { ZOO },
      } = await setupTest()
      await ZOO.pause()
      await expect(ZOO.transfer(signers[1].address, signers[2].address)).to.be.rejectedWith('Pausable: paused')
    })

    it('disallows a to address that is blacklisted', async () => {
      const {
        signers,
        tokens: { ZOO },
      } = await setupTest()
      await ZOO.blacklistAddress(signers[1].address)
      await expect(ZOO.transfer(signers[1].address, 2000)).to.be.rejectedWith('Address is on blacklist')
    })

    it('disallows a from address that is blacklisted', async () => {
      const {
        signers,
        tokens: { ZOO },
      } = await setupTest()
      await ZOO.blacklistAddress(signers[2].address)
      await expect(ZOO.connect(signers[2]).transfer(signers[2].address, 2000)).to.be.rejectedWith('Address is on blacklist')
    })
    it('transfers', async () => {
      const {
        signers,
        tokens: { ZOO },
      } = await setupTest()
      await ZOO.mint(signers[0].address, 2000000000000)
      await expect(ZOO.transfer(signers[2].address, 2000)).not.to.be.rejected
      expect(await ZOO.balanceOf(signers[2].address)).to.be.equal(2000)
    })
  })

  describe('configure', async () => {
    it('allows owner to upgrade bridge through configure', async () => {
      const {
        signers,
        tokens: { ZOO, Bridge },
      } = await setupTest()
      const beforeAddr = await ZOO.bridge()
      await ZOO.configure(signers[0].address)
      expect(await ZOO.bridge()).not.to.equal(beforeAddr)
    })

    it('prevents non-owner from calling configure', async () => {
      const {
        signers,
        tokens: { ZOO },
      } = await setupTest()
      await expect(ZOO.connect(signers[1]).configure(signers[2].address)).to.be.rejectedWith('Ownable: caller is not the owner')
    })
  })

  describe('bridgeMint', async () => {
    let token: any
    let bridge: any

    beforeEach(async () => {
      const {
        signers,
        tokens: { ZOO, Bridge },
      } = await setupTest()
      await ZOO.configure(Bridge.address)
      // await Bridge.setToken(ZOO)
      token = ZOO
      bridge = Bridge
    })

    it('disallows anyone not the bridge to call mint', async () => {
      const { signers } = await setupTest()
      const caller = signers[1].address
      expect(await token.balanceOf(caller)).to.be.equal(0)
      await expect(token.bridgeMint(caller, 10000)).to.be.revertedWith('Caller is not the bridge')
      expect(await token.balanceOf(caller)).to.be.equal(0)
    })

    it('allows the bridge to call mint')
  })
})
