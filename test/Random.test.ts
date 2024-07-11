import { ethers } from 'hardhat'
import { expect } from 'chai'
import { solidity } from 'ethereum-waffle'
import chai from 'chai'
import { Random } from '../types/Random'

chai.use(solidity)

let random: Random
let signers: any
let reveal = ethers.utils.id('' + Math.random())

describe('Commit Reveal Test', async () => {
  beforeEach(async () => {
    signers = await ethers.getSigners()
    const randomFactory = await ethers.getContractFactory('Random', signers[0])
    random = (await randomFactory.deploy()) as Random
    await random.deployed()
  })

  it('Should commit a hash, reveal a hash, and return a random number', async () => {
    console.log(reveal)

    // Create unique hash from the randomized hash
    const commit = await random.getHash(reveal)

    // Commit the unique hash
    const commitTx = await random.commit(commit)

    const commitReceipt = await commitTx.wait()

    // Gets the commit, block number, reveal status
    const commits = await random.commits(signers[0].address)

    // Reveals the commit
    const revealTx = await random.reveal(reveal)

    // Transaction receipt
    const revealReceipt = await revealTx.wait()

    // Random number is generated from the RevealHash event
    const randomNum = revealReceipt.events[0].args.random

    // Returned commit has to be a 66 character long string
    expect(commit.length).to.equal(66)

    // Returned commits array has to have a length of 3
    expect(commits.length).to.equal(3)

    // Returned commit from the commits array has to be a 66 character long string
    expect(commits[0].length).to.be.equal(66)

    // The commit returned from the commits array and the commit created from the getHash function have
    // to be the same
    expect(commits[0]).to.equal(commit)

    // CommitHash should be emitted
    expect(commitReceipt.events[0].event).to.equal('CommitHash')

    // Sender should be equal to the address of signer 0
    expect(commitReceipt.events[0].args.sender).to.equal(signers[0].address)

    // DataHash should be equal to the hash created from getHash
    expect(commitReceipt.events[0].args.dataHash).to.equal(commit)

    // Block number should be greater than 0
    expect(parseInt(commits[1]._hex)).to.be.greaterThan(0)

    // The commit reveal status should be false if never revealed
    expect(commits[2]).to.be.false

    // The randomNum should never be above 100
    expect(randomNum).to.be.lessThanOrEqual(100)

    // RevealHash should be emitted
    expect(revealReceipt.events[0].event).to.equal('RevealHash')
  })
})
