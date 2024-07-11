import { deployments, ethers, getNamedAccounts, upgrades } from 'hardhat'

// import { DLUX__factory, Media__factory, Market__factory, Token, LuxDrop } from '../types';

// import { Media } from '../types/Media';
// import { LuxToken } from '../types/LuxToken';
// import { Faucet } from '../types/Faucet';
// import { Market } from '../types/Market';
// import { DLUX } from '../types/DLUX';
// import configureGame from '../utils/configureGame';
import { Contract, BigNumber, Bytes, BytesLike, utils } from 'ethers'

import { solidity } from 'ethereum-waffle'
import { hex } from 'chalk'

import { requireDependencies, setupTestFactory } from './utils'
import { MaxUint256 } from '@ethersproject/constants'
const { expect } = requireDependencies()

const setupTest = setupTestFactory(['Media', 'Market', 'Bridge', 'LUX'])

// let luxToken: any
// let luxDrop: any
// let luxMarket: any
let luxDAO: any
// let luxMedia: any
let appSigners: any
// let mintAmt = 100000000
// let owner
// let mediaAddress: string
// let marketAddress: string
// let nftPrice: any

class Helper {
  public LUX: Contract
  public Drop: Contract
  public owner: any
  public Market: Contract
  public Media: Contract
  public luxDAO: Contract
  public nftPrice: BigNumber
  // public signers: any

  constructor() {}

  public static async setup() {
    const inst = new Helper()
    await deployments.createFixture(async ({ deployments, getNamedAccounts, ethers }, options) => {
      const {
        signers,
        tokens: { LUX, Market, Media, DLUX, Drop },
      } = await setupTest()
      const contracts = await deployments.fixture() // ensure you start from a fresh deployments

      appSigners = signers
      inst.LUX = await ethers.getContractAt('LUX', contracts.LUX.address, signers[0])
      inst.Market = await ethers.getContractAt('Market', contracts.Market.address, signers[0])
      inst.Media = await ethers.getContractAt('Media', contracts.Media.address, signers[0])
      inst.luxDAO = await ethers.getContractAt('DLUX', contracts.DLUX.address, signers[0])
      inst.Drop = await ethers.getContractAt('Drop', contracts.Drop.address, signers[0])

      // this mint is executed once and then createFixture will ensure it is snapshotted
      // await luxToken.mint(tokenOwner.deployer, 100000).then(tx => tx.wait());

      const getDeployer = await getNamedAccounts()

      inst.owner = getDeployer.deployer
      inst.nftPrice = await inst.Drop.nftPrice(1)
    })()

    return inst
  }

  async getEventData(tx: any, eventName: String) {
    const { events } = await tx.wait()
    let args: any[] = []
    for (let i = events.length - 1; i >= 0; i--) {
      let evt = events[i]
      if (evt.event === eventName) {
        args = evt.args
        break
      }
    }
    return args
  }

  async breedAnimals() {}
  async freeAnimal(id: Number) {}
  async hatchNFT() {}

  async buyNFT(signerIdx: number = 0) {
    // await this.luxToken.connect(this.luxDAO.address).approve(addr, this.nftPrice)
    await this.LUX.approve(this.luxDAO.address, MaxUint256)
    const tx = await this.luxDAO.buyNFTs(1, 1)
    const args = await this.getEventData(tx, 'BuyNFT')
    return { from_evt: args['from'], nftID: args['nftID'] }
  }

  async hatchAnimal(token_id: String) {
    const tx = await this.luxDAO.hatchNFT(1, token_id)
    const args = await this.getEventData(tx, 'Hatch')
    return { nftID: args['nftID'], tokenID: args['tokenID'] }
  }

  async breedHybrid() {
    const { nftID: nft_id_1 } = await this.buyNFT()
    const { nftID: nft_id_2 } = await this.buyNFT()

    const { tokenID: animal_id_1 } = await this.hatchAnimal(nft_id_1)
    const { tokenID: animal_id_2 } = await this.hatchAnimal(nft_id_2)

    const hybridNFT = await this.luxDAO.breedAnimals(1, parseInt(animal_id_1), parseInt(animal_id_2))

    return hybridNFT.id
  }
}

describe('DLUX', () => {

  // it('can buy an nft and hatch an animal from the nft', async () => {
  //   const h = await Helper.setup()

  //   await h.LUX.approve(h.luxDAO.address, h.nftPrice)

  //   const { nftID: nft1_id } = await h.buyNFT(1)
  //   // const { nftID: nft2_id } = await h.buyNFT(1)

  //   const { nftID: animal1_id } = await h.hatchAnimal(nft1_id)
  //   // const { nftID: animal2_id } = await h.hatchAnimal(nft2_id)

  //   console.log('hathced', animal1_id)

  //   expect(animal1_id).to.equal(nft1_id)
  //   // expect(animal2_id).to.equal(nft2_id)
  // })

  it('sets the owner of the nft to the buyer', async () => {
    const h = await Helper.setup()

    await h.LUX.approve(h.luxDAO.address, h.nftPrice)
    const { from_evt: nft_buyer, nftID: nft1_id } = await h.buyNFT(1)

    expect(nft_buyer).to.equal(h.owner)

    expect(parseInt(nft1_id._hex)).to.equal(1)
  })

  it('assigns the luxKeyper owner', async () => {
    const h = await Helper.setup()
    const luxDropOwner: string = await h.luxDAO.owner()

    expect(luxDropOwner).to.equal(h.owner)
  })

  // // Hatch nfts into animals
  // await luxDAO.methods.hatchNFT(1, 1).send({ from: account }).then((res) => {
  //   console.log('hatchNFT', res);
  // })

  // await luxDAO.methods.hatchNFT(1, 2).send({ from: account }).then((res) => {
  //   console.log('hatchNFT', res);
  // })

  //    await luxDAO.hatchNFT(1, 1)

  //   await luxDAO.hatchNFT(1, 2)

  // Breed animals into hybrid nft
  // await luxDAO.methods.breedAnimals(1, 3, 4).send({ from: account }).then((res) => {
  //   console.log('breedAnimals', res)
  // })

  //  await luxDAO.breedAnimals(1, 3, 4)

  // Hatch hybrid nft into hybrid animal
  // await luxDAO.methods.hatchNFT(1, 5).send({ from: account }).then((res) => {
  //   console.log('hatchNFT', res);
  // })

  // await luxDAO.hatchNFT(1, 5)

  // Free animal and collect yield
  // await luxDAO.methods.freeAnimal(6).send({ from: account }).then((res) => {
  //     console.log('freeAnimal', res);
  //  })

  // await luxDAO.freeAnimal(6)

  // if (tokenBalance > 1) {
  //    const tokenID = await luxMedia.methods
  //       .tokenOfOwnerByIndex(account, 1)
  //       .call();
  //    console.log("tokenID", tokenID);
  //    const tokenURI = await luxMedia.methods.tokenURI(tokenID).call();
  //    console.log("tokenURI", tokenURI);
  //    const token = await luxDAO.methods.tokens(tokenID).call();
  //    console.log("token", token);
  // }

  // TOTAL NFTS AFTER THIS TEST = 2
})
