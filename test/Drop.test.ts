import { ethers } from 'hardhat'
import { Drop } from '../types/Drop'
import chai, { expect } from 'chai'
import { BigNumber, Bytes, BytesLike, utils } from 'ethers'

let drop: any
let signers: any
let mintAmt = 100000000
let owner

const TOKEN_URI = 'idx.zoolabs.io/token/'
const META_URI = 'idx.zoolabs.io/meta/'

describe('Drop', () => {
  beforeEach(async () => {
    signers = await ethers.getSigners()
    owner = signers[0]

    // Deploy drop
    const Drop = await ethers.getContractFactory('Drop', owner)
    drop = await Drop.deploy('Gen1')

    // Set default eggs on Drop
    const eggs = [
      {
        name: 'baseEgg',
        price: 210,
        supply: 16000,
        tokenURI: 'https://db.zoolabs/egg.jpg',
        metadataURI: 'https://db.zoolabs.org/egg.json',
      },
      {
        name: 'hybridEgg',
        price: 0,
        supply: 0,
        tokenURI: 'https://db.zoolabs/hybrid.jpg',
        metadataURI: 'https://db.zoolabs.org/hybrid.json',
      },
    ]

    await Promise.all(
      eggs.map((v) => {
        drop.setEgg(v.name, v.price, v.supply, v.tokenURI, v.metadataURI)
      }),
    )

    // configure our eggs to be base / hybrid egg
    drop.configureEggs('baseEgg', 'hybridEgg')

    await Promise.all(
      eggs.map((v) => {
        console.log('Add Egg:', v.name)
        drop.setEgg(v.name, v.price, v.supply, v.tokenURI, v.metadataURI)
      }),
    )

    drop.setEgg('baseEgg')
    await drop.deployed()
  })

  it('Should have current supply equal total supply', async () => {
    let currentSupply = await drop.currentSupply()
    expect(currentSupply.toNumber()).to.equal((await drop.totalSupply()).toNumber())
  })

  it('Should add Animal', async () => {
    await drop.addAnimal('Pug', 100, 'Common', 5500, TOKEN_URI, META_URI)

    const Animal = await drop.animals('Pug')
    const tokenURI = await drop.tokenURI(Animal.name)

    expect(Animal.name).to.equal('Pug')
    expect(tokenURI).to.equal(TOKEN_URI)
  })

  it('Should add an Hybrid', async () => {
    await drop.addHybrid('Puggy', 'Pug', 'Pug', 120, TOKEN_URI, META_URI)

    const Hybrid = await drop.hybrids('PugPug')
    const tokenURI = await drop.tokenURI('Puggy')

    expect(Hybrid.name).to.equal('Puggy')
    expect(tokenURI).to.equal(TOKEN_URI)
  })

  it('Should revert when adding a animal not as owner', async () => {
    drop = drop.connect(signers[1])
    try {
      const tx = await drop.addAnimal('Pug', 100, 'Common', 5500, TOKEN_URI, META_URI)
    } catch (e) {
      expect(e.message.includes('Ownable: caller is not the owner')).to.be.true
    }
  })

  it('Should revert when adding a hybrid animal not as owner', async () => {
    drop = drop.connect(signers[1])
    try {
      const tx = await drop.addHybrid('Puggy', 'Pug', 'Pug', 120, TOKEN_URI, META_URI)
    } catch (e) {
      expect(e.message.includes('Ownable: caller is not the owner')).to.be.true
    }
  })

  it('Should set & get egg price', async () => {
    drop = drop.connect(signers[0])
    const eggPrice = (await drop.eggPrice()).toNumber()
    expect(eggPrice).to.equal(210) // default eggPrice

    await drop.connect(signers[0]).setEggPrice(333) //set a new price

    const newPrice = (await drop.eggPrice()).toNumber()
    expect(newPrice).to.equal(333) // gets the new eggPrice
  })

  it('Should revert when setting egg price as non owner', async () => {
    drop = drop.connect(signers[1])
    try {
      const tx = await drop.setEggPrice(333)
    } catch (e) {
      expect(e.message.includes('Ownable: caller is not the owner')).to.be.true
    }
  })

  it('Should set tokenURI for Animal', async () => {
    drop = drop.connect(signers[0])
    await drop.setTokenURI('pug', 'pug.com')
    let tokenURI = await drop.tokenURI('pug')
    expect(tokenURI).to.equal('pug.com')
  })

  it('Should revert when setting tokenURI as non owner', async () => {
    drop = drop.connect(signers[1])
    try {
      const tx = await drop.setTokenURI('pug', 'pug.com')
    } catch (e) {
      expect(e.message.includes('Ownable: caller is not the owner')).to.be.true
    }
  })

  it('Should set metadataURI for a pug', async () => {
    drop = drop.connect(signers[0])
    const res = await drop.setMetadataURI('pug', 'pug.com/meta')
    const metadataURI = await drop.getMetadataURI('pug')
    expect(metadataURI).to.equal('pug.com/meta')
  })

  it('Should revert when setting tokenURI as non owner', async () => {
    drop = drop.connect(signers[1])
    try {
      const tx = await drop.setMetadataURI('pug', 'pug.com')
    } catch (e) {
      expect(e.message.includes('Ownable: caller is not the owner')).to.be.true
    }
  })
})
