import { setupTestFactory, requireDependencies } from './utils'
import { ethers, waffle } from 'hardhat'
import { Contract, BigNumber, ContractFactory, Wallet } from 'ethers'
import { Signer } from '@ethersproject/abstract-signer'
import { Savage as ISavage } from '../types'

import { IERC20 } from '../types'

const { expect } = requireDependencies()
const { deployContract, deployMockContract } = waffle

const setupTest = setupTestFactory(['UniswapV2Factory', 'UniswapV2Router02', 'Savage', 'Z1', 'BNB', 'ZOO'])

describe('Savage', function () {
  let savage: Contract
  let factory: Contract
  let router: Contract
  let zoo: Contract
  let bnb: Contract
  let z1: Contract
  let signers: Signer[]
  let sender: any

  const tril = ethers.utils.parseEther('1000000000000')
  const amountZ1 = ethers.utils.parseUnits('2180913677.035819786465972231', 18)
  const amountBNB = ethers.utils.parseUnits('2019.717141295805250967', 18)
  const finalBNB = ethers.utils.parseUnits('2010', 18)
  const amountIn = tril
  const amountOutMin = ethers.utils.parseUnits('1990', 18)

  beforeEach(async () => {
    const {
      signers,
      deployments,
      tokens: { UniswapV2Factory, UniswapV2Router02, Savage, Z1, BNB, ZOO },
    } = await setupTest()
    sender = signers[0]
    factory = UniswapV2Factory
    router = UniswapV2Router02
    bnb = BNB
    savage = Savage
    z1 = Z1
    zoo = ZOO
  })

  it('can be deployed', async () => {
    expect(savage).not.to.be.null
  })

  it('sets the factory correctly on router', async () => {
    const rfactory = await router.factory()
    expect(rfactory).to.equal(factory.address)
  })

  it.only('removes BNB from old LP', async () => {
    const txn = await factory.createPair(z1.address, bnb.address);
    await txn.wait();
    const pair = await factory.getPair(z1.address, bnb.address)

    const amountToSender = amountZ1.add(amountIn)

    const originalBalance = await z1.balanceOf(sender.address)

    await bnb.mint(sender.address, amountBNB)
    await z1.mint(sender.address, amountToSender)
    await zoo.mint(savage.address, amountZ1)

    await bnb.approve(router.address, amountBNB)
    await z1.approve(router.address, amountZ1)

    expect(await z1.balanceOf(sender.address)).to.be.equal(amountToSender.add(originalBalance));
    expect(await bnb.balanceOf(sender.address)).to.be.equal(amountBNB);

    expect(await z1.balanceOf(pair)).to.be.equal(0);
    expect(await bnb.balanceOf(pair)).to.be.equal(0);

    // Add liquidity
    await router.addLiquidity(
      z1.address,
      bnb.address,
      amountZ1, amountBNB,
      100, 100,
      sender.address,
      2e9
    )

    expect(await z1.balanceOf(sender.address)).to.be.equal(tril)
    expect(await bnb.balanceOf(sender.address)).to.be.equal(0)
    expect(await bnb.balanceOf(router.address)).to.be.equal(0)

    expect(await z1.balanceOf(pair)).to.be.equal(amountZ1)
    expect(await bnb.balanceOf(pair)).to.be.equal(amountBNB)

    await z1.approve(savage.address, amountIn)
    await savage.drainPool()

    // await zoo.unpause()

    expect(await bnb.balanceOf(savage.address)).to.be.at.least(finalBNB)

    await savage.launchPool()

    await savage.withdrawAll(sender.address)
    expect(await bnb.balanceOf(savage.address)).to.be.equal(0)
  })
})
