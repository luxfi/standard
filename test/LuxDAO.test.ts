import { deployments, ethers, getNamedAccounts, upgrades } from 'hardhat'

// import { ZooKeeper__factory, Media__factory, Market__factory, Token, ZooDrop } from '../types';

// import { Media } from '../types/Media';
// import { ZooToken } from '../types/ZooToken';
// import { Faucet } from '../types/Faucet';
// import { Market } from '../types/Market';
// import { ZooKeeper } from '../types/ZooKeeper';
// import configureGame from '../utils/configureGame';
import { Contract, BigNumber, Bytes, BytesLike, utils } from 'ethers'

import { solidity } from 'ethereum-waffle'
import { hex } from 'chalk'

import { requireDependencies, setupTestFactory } from './utils'
const { expect } = requireDependencies()

const setupTest = setupTestFactory(['Media', 'Market', 'Bridge', 'ZOO'])

// let zooToken: any
// let zooDrop: any
// let zooMarket: any
let zooKeeper: any
// let zooMedia: any
// let signers: any
// let mintAmt = 100000000
// let owner
// let mediaAddress: string
// let marketAddress: string
// let eggPrice: any

class Helper {
  public ZOO: Contract
  public Drop: Contract
  public owner: any
  public Market: Contract
  public Media: Contract
  public zooKeeper: Contract
  public eggPrice: BigNumber
  public signers: any

  constructor() {}

  public static async setup() {
    const inst = new Helper()
    await deployments.createFixture(async ({ deployments, getNamedAccounts, ethers }, options) => {
      const {
        signers,
        tokens: { ZOO, Market, Media, ZooKeeper, Drop },
      } = await setupTest()
      const contracts = await deployments.fixture() // ensure you start from a fresh deployments

      inst.signers = signers
      inst.ZOO = await ethers.getContractAt('ZOO', contracts.ZOO.address, signers[0])
      inst.Market = await ethers.getContractAt('Market', contracts.Market.address, signers[0])
      inst.Media = await ethers.getContractAt('Media', contracts.Media.address, signers[0])
      inst.zooKeeper = await ethers.getContractAt('ZooKeeper', contracts.ZooKeeper.address, signers[0])
      inst.Drop = await ethers.getContractAt('Drop', contracts.Drop.address, signers[0])

      // this mint is executed once and then createFixture will ensure it is snapshotted
      // await zooToken.mint(tokenOwner.deployer, 100000).then(tx => tx.wait());

      const getDeployer = await getNamedAccounts()

      inst.owner = getDeployer.deployer
      inst.eggPrice = await inst.Drop.eggPrice()
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
  async hatchEgg() {}

  async buyEgg(signerIdx: number = 0) {
    // await this.zooToken.connect(this.zooKeeper.address).approve(addr, this.eggPrice)
    await this.ZOO.approve(this.zooKeeper.address, this.eggPrice)
    const tx = await this.zooKeeper.buyEgg(1)
    const args = await this.getEventData(tx, 'BuyEgg')
    return { from_evt: args['from'], eggID: args['eggID'] }
  }

  async hatchAnimal(token_id: String) {
    const tx = await this.zooKeeper.hatchEgg(1, token_id)
    const args = await this.getEventData(tx, 'Hatch')
    return { eggID: args['eggID'], tokenID: args['tokenID'] }
  }

  async breedHybrid() {
    const { eggID: egg_id_1 } = await this.buyEgg()
    const { eggID: egg_id_2 } = await this.buyEgg()

    const { tokenID: animal_id_1 } = await this.hatchAnimal(egg_id_1)
    const { tokenID: animal_id_2 } = await this.hatchAnimal(egg_id_2)

    const hybridEgg = await this.zooKeeper.breedAnimals(1, parseInt(animal_id_1), parseInt(animal_id_2))

    return hybridEgg.id
  }
}

describe('ZooKeeper', () => {
  describe('upgradable', async () => {
    it('references do not change', async () => {
      const {
        tokens: { ZOO, Market, Media, Bridge },
      } = await setupTest()
      const ZK = await ethers.getContractFactory('ZooKeeper')
      const inst = await upgrades.deployProxy(ZK, [])
      await inst.configure(Media.address, ZOO.address, Bridge.address)

      expect(await inst.market()).to.equal(Market.address)
      expect(await inst.media()).to.equal(Media.address)
      expect(await inst.zoo()).to.equal(ZOO.address)
      expect(await inst.bridge()).to.equal(Bridge.address)

      const ZK2 = await ethers.getContractFactory('ZooKeeperV2')
      const upgraded = await upgrades.upgradeProxy(inst.address, ZK2)

      expect(await upgraded.market()).to.equal(Market.address)
      expect(await upgraded.media()).to.equal(Media.address)
      expect(await upgraded.zoo()).to.equal(ZOO.address)
      expect(await upgraded.bridge()).to.equal(Bridge.address)
      // expect(value.toString()).to.equal([Market.address, Media.address, ZOO.address, Bridge.address]);
    })

    it('upgrades functionality', async () => {
      const {
        tokens: { ZOO, Market, Media, Bridge },
      } = await setupTest()
      const ZK = await ethers.getContractFactory('ZooKeeper')
      const ZK2 = await ethers.getContractFactory('ZooKeeperV2')

      const inst = await upgrades.deployProxy(ZK, [])
      expect(inst.newMethod).to.undefined;

      await inst.configure(Media.address, ZOO.address, Bridge.address)

      const upgraded = await upgrades.upgradeProxy(inst.address, ZK2)
      await expect(upgraded.newMethod).not.to.be.undefined;
      expect(await upgraded.newMethod()).to.be.equal(42);
    })
  })

  it('can buy an egg and hatch an animal from the egg', async () => {
    const h = await Helper.setup()

    await h.ZOO.approve(h.zooKeeper.address, h.eggPrice)

    const { eggID: egg1_id } = await h.buyEgg(1)
    const { eggID: egg2_id } = await h.buyEgg(1)

    const { eggID: animal1_id } = await h.hatchAnimal(egg1_id)
    const { eggID: animal2_id } = await h.hatchAnimal(egg2_id)

    expect(animal1_id).to.equal(egg1_id)
    expect(animal2_id).to.equal(egg2_id)
  })

  it('sets the owner of the egg to the buyer', async () => {
    const h = await Helper.setup()

    await h.ZOO.approve(h.zooKeeper.address, h.eggPrice)
    const { from_evt: egg_buyer, eggID: egg1_id } = await h.buyEgg(1)

    expect(egg_buyer).to.equal(h.owner)

    expect(parseInt(egg1_id._hex)).to.equal(1)
  })

  it('assigns the zooKeyper owner', async () => {
    const h = await Helper.setup()
    const zooDropOwner: string = await h.zooKeeper.owner()

    expect(zooDropOwner).to.equal(h.owner)
  })

  // // Hatch eggs into animals
  // await zooKeeper.methods.hatchEgg(1, 1).send({ from: account }).then((res) => {
  //   console.log('hatchEgg', res);
  // })

  // await zooKeeper.methods.hatchEgg(1, 2).send({ from: account }).then((res) => {
  //   console.log('hatchEgg', res);
  // })

  //    await zooKeeper.hatchEgg(1, 1)

  //   await zooKeeper.hatchEgg(1, 2)

  // Breed animals into hybrid egg
  // await zooKeeper.methods.breedAnimals(1, 3, 4).send({ from: account }).then((res) => {
  //   console.log('breedAnimals', res)
  // })

  //  await zooKeeper.breedAnimals(1, 3, 4)

  // Hatch hybrid egg into hybrid animal
  // await zooKeeper.methods.hatchEgg(1, 5).send({ from: account }).then((res) => {
  //   console.log('hatchEgg', res);
  // })

  // await zooKeeper.hatchEgg(1, 5)

  // Free animal and collect yield
  // await zooKeeper.methods.freeAnimal(6).send({ from: account }).then((res) => {
  //     console.log('freeAnimal', res);
  //  })

  // await zooKeeper.freeAnimal(6)

  // if (tokenBalance > 1) {
  //    const tokenID = await zooMedia.methods
  //       .tokenOfOwnerByIndex(account, 1)
  //       .call();
  //    console.log("tokenID", tokenID);
  //    const tokenURI = await zooMedia.methods.tokenURI(tokenID).call();
  //    console.log("tokenURI", tokenURI);
  //    const token = await zooKeeper.methods.tokens(tokenID).call();
  //    console.log("token", token);
  // }

  // TOTAL EGGS AFTER THIS TEST = 2
})
