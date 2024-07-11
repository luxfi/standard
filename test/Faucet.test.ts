import { ethers } from 'hardhat'
import { ZOO } from '../types'
import { Faucet } from '../types/Faucet'
import { expect } from 'chai'
import { BigNumber } from 'ethers'

let zooToken: any
let zooFaucet: any
let signers: any
let mintAmt = 100000000
let owner

describe('Test Faucet', () => {
  beforeEach(async () => {
    signers = await ethers.getSigners()

    const zooTokenFactory = await ethers.getContractFactory('ZOO', signers[0])

    zooToken = (await zooTokenFactory.deploy()) as ZOO
    await zooToken.deployed()

    const zooFaucetFactory = await ethers.getContractFactory('Faucet', signers[0])

    zooFaucet = (await zooFaucetFactory.deploy(zooToken.address)) as Faucet
    await zooFaucet.deployed()

    owner = signers[0]
  })

  it('Should get the Faucet owner', async () => {
    const faucetOwner: string = await zooFaucet.owner()

    expect(faucetOwner).to.equal(owner.address)
  })

  it('Should mint 100,000,000 from ZOO to Faucet', async () => {
    const faucetPreBal: BigNumber = await zooToken.balanceOf(zooFaucet.address)
    await zooToken.mint(zooFaucet.address, mintAmt)
    const faucetPostBal: BigNumber = await zooToken.balanceOf(zooFaucet.address)
    expect(parseInt(faucetPreBal._hex)).to.equal(0)
    expect(parseInt(faucetPostBal._hex)).to.equal(mintAmt)
  })

  it('Should be able transfer 10k ZOO from Faucet', async () => {
    await zooToken.mint(zooFaucet.address, mintAmt)

    const rate = 1000

    for (var i = 0; i < signers.length; i++) {
      await zooFaucet.fund(signers[i].address, 10)

      const signerBalances = await zooToken.balanceOf(signers[i].address)

      // Expect the balances to be 10K(10 * rate(1000) = 10K)
      expect(parseInt(signerBalances)).to.equal(10 * rate)
    }
  })

  it('Should be able withdraw ZOO from Faucet', async () => {
    // Creates 100 million ZOO tokens and allocates to the Faucet
    await zooToken.mint(zooFaucet.address, mintAmt)

    // The Faucet balance should be 100 million
    const faucetInitialBal = await zooToken.balanceOf(zooFaucet.address)

    // 10M tokens
    const rate = 10000000

    // The amount being withdrawn from the Faucet
    const faucetWithdrawAmt = rate * (10 ** 18)

    for (var i = 0; i < signers.length; i++) {
      await zooFaucet.fund(signers[i].address, 10)

      // Signer balances
      const signerBalances = await zooToken.balanceOf(signers[i].address)

      // Signer balances should be 10K ZOO
      expect(parseInt(signerBalances)).to.equal(10 * rate)
    }

    // Owner Zoo balance should be 10k
    const ownerBal = await zooToken.balanceOf(owner.address)

    // Faucet balance should decreased by 200k
    const faucetBalPostFund = await zooToken.balanceOf(zooFaucet.address)

    // Withdraw all Zoo from the Faucet to the owners wallet
    await zooFaucet.withdraw()

    // Faucet balance after withdrawTok should be 0
    const faucetBalPostWithdraw = await zooToken.balanceOf(zooFaucet.address)

    // Owner should acquire all ZOO after withdrawal
    const ownerBalPostWithdraw = await zooToken.balanceOf(owner.address)

    // Expect the owner balance to increase by the faucetBalPostFund amount
    expect(parseInt(ownerBalPostWithdraw)).to.equal(parseInt(ownerBal) + parseInt(faucetBalPostFund))

    // Expect the Faucet balance to be 100 million
    expect(parseInt(faucetInitialBal)).to.equal(mintAmt)

    // Expect the balance to equal 99800000
    // faucetInitialBal(100, 000, 000) - faucetWithdrawAmt(200, 000) = 99800000
    expect(parseInt(faucetBalPostFund)).to.equal(parseInt(faucetInitialBal) - faucetWithdrawAmt)

    // Expect the Faucet balance to be 0
    expect(parseInt(faucetBalPostWithdraw)).to.equal(0)
  })
})
