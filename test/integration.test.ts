// @ts-ignore
import { ethers } from 'hardhat'
import chai, { expect } from 'chai'
import asPromised from 'chai-as-promised'
import { deployOtherNFTs, deployToken, deployProtocol, mint, ONE_ZOO, TENTH_ZOO, THOUSANDTH_ZOO, TWO_ZOO } from './utils'
import { Auction, Market, Media, ZOO, TestERC721 } from '../types'
import { BigNumber, Signer } from 'ethers'

chai.use(asPromised)

const ONE_DAY = 24 * 60 * 60

// helper function so we can parse numbers and do approximate number calculations, to avoid annoying gas calculations
const smallify = (bn: BigNumber) => bn.div(THOUSANDTH_ZOO).toNumber()

describe.skip('integration', () => {
  let market: Market
  let media: Media
  let token: ZOO
  let auction: Auction
  let otherNft: TestERC721
  let deployer, creator, owner, curator, bidderA, bidderB, otherUser: Signer
  let deployerAddress, ownerAddress, creatorAddress, curatorAddress, bidderAAddress, bidderBAddress, otherUserAddress: string

  async function deploy(): Promise<Auction> {
    const ZooAuction = await ethers.getContractFactory('ZooAuction')
    const auctionHouse = await ZooAuction.deploy()
    await auctionHouse.configure(media.address, token.address)
    return auctionHouse as Auction
  }

  beforeEach(async () => {
    await ethers.providers[0].send('hardhat_reset', [])
    ;[deployer, creator, owner, curator, bidderA, bidderB, otherUser] = await ethers.getSigners()
    ;[deployerAddress, creatorAddress, ownerAddress, curatorAddress, bidderAAddress, bidderBAddress, otherUserAddress] = await Promise.all(
      [deployer, creator, owner, curator, bidderA, bidderB].map((s) => s.getAddress()),
    )
    token = await deployToken()
    const contracts = await deployProtocol(token.address)
    const nfts = await deployOtherNFTs()
    market = contracts.market
    media = contracts.media
    auction = await deploy()
    otherNft = nfts.test
    await mint(media.connect(creator))
    await otherNft.mint(creator.address, 0)
    await media.connect(creator).transferFrom(creatorAddress, ownerAddress, 0)
    await otherNft.connect(creator).transferFrom(creatorAddress, ownerAddress, 0)
  })

  describe('Auction with no curator', async () => {
    async function run() {
      console.log('connect media')
      await media.connect(owner).approve(auction.address, 0)
      console.log('connect auction')
      await auction.connect(owner).createAuction(0, media.address, ONE_DAY, TENTH_ZOO, ethers.constants.AddressZero, 0, ethers.constants.AddressZero)
      console.log('createbid auction')
      await auction.connect(bidderA).createBid(0, ONE_ZOO, { value: ONE_ZOO })
      await auction.connect(bidderB).createBid(0, TWO_ZOO, { value: TWO_ZOO })
      await ethers.providers[0].send('evm_setNextBlockTimestamp', [Date.now() + ONE_DAY])
      await auction.connect(otherUser).endAuction(0)
    }

    it('should transfer the NFT to the winning bidder', async () => {
      await run()
      expect(await media.ownerOf(0)).to.eq(bidderBAddress)
    })

    it('should withdraw the winning bid amount from the winning bidder', async () => {
      const beforeBalance = await ethers.providers[0].getBalance(bidderBAddress)
      await run()
      const afterBalance = await ethers.providers[0].getBalance(bidderBAddress)

      expect(smallify(beforeBalance.sub(afterBalance))).to.be.approximately(smallify(TWO_ZOO), smallify(TENTH_ZOO))
    })

    it('should refund the losing bidder', async () => {
      const beforeBalance = await ethers.providers[0].getBalance(bidderAAddress)
      await run()
      const afterBalance = await ethers.providers[0].getBalance(bidderAAddress)

      expect(smallify(beforeBalance)).to.be.approximately(smallify(afterBalance), smallify(TENTH_ZOO))
    })

    it('should pay the auction creator', async () => {
      const beforeBalance = await ethers.providers[0].getBalance(ownerAddress)
      await run()
      const afterBalance = await ethers.providers[0].getBalance(ownerAddress)

      // 15% creator fee -> 2ZOO * 85% = 1.7 ZOO
      expect(smallify(afterBalance)).to.be.approximately(smallify(beforeBalance.add(TENTH_ZOO.mul(17))), smallify(TENTH_ZOO))
    })

    it('should pay the token creator in ZooToken', async () => {
      const beforeBalance = await token.balanceOf(creatorAddress)
      await run()
      const afterBalance = await token.balanceOf(creatorAddress)

      // 15% creator fee -> 2 ZOO * 15% = 0.3 ZooToken
      expect(afterBalance).to.eq(beforeBalance.add(THOUSANDTH_ZOO.mul(300)))
    })
  })

  describe('ZOO auction with curator', () => {
    async function run() {
      await media.connect(owner).approve(auction.address, 0)
      await auction.connect(owner).createAuction(0, media.address, ONE_DAY, TENTH_ZOO, curatorAddress, 20, ethers.constants.AddressZero)
      await auction.connect(curator).setAuctionApproval(0, true)
      await auction.connect(bidderA).createBid(0, ONE_ZOO, { value: ONE_ZOO })
      await auction.connect(bidderB).createBid(0, TWO_ZOO, { value: TWO_ZOO })
      await ethers.providers[0].send('evm_setNextBlockTimestamp', [Date.now() + ONE_DAY])
      await auction.connect(otherUser).endAuction(0)
    }

    it('should transfer the NFT to the winning bidder', async () => {
      await run()
      expect(await media.ownerOf(0)).to.eq(bidderBAddress)
    })

    it('should withdraw the winning bid amount from the winning bidder', async () => {
      const beforeBalance = await ethers.provider.getBalance(bidderBAddress)
      await run()
      const afterBalance = await ethers.provider.getBalance(bidderBAddress)

      expect(smallify(beforeBalance.sub(afterBalance))).to.be.approximately(smallify(TWO_ZOO), smallify(TENTH_ZOO))
    })

    it('should refund the losing bidder', async () => {
      const beforeBalance = await ethers.provider.getBalance(bidderAAddress)
      await run()
      const afterBalance = await ethers.provider.getBalance(bidderAAddress)

      expect(smallify(beforeBalance)).to.be.approximately(smallify(afterBalance), smallify(TENTH_ZOO))
    })

    it('should pay the auction creator', async () => {
      const beforeBalance = await ethers.provider.getBalance(ownerAddress)
      await run()
      const afterBalance = await ethers.provider.getBalance(ownerAddress)

      expect(smallify(afterBalance)).to.be.approximately(
        // 15% creator share + 20% curator fee  -> 1.7 ZOO * 80% = 1.36 ZOO
        smallify(beforeBalance.add(TENTH_ZOO.mul(14))),
        smallify(TENTH_ZOO),
      )
    })

    it('should pay the token creator in ZooToken', async () => {
      const beforeBalance = await token.balanceOf(creatorAddress)
      await run()
      const afterBalance = await token.balanceOf(creatorAddress)

      // 15% creator fee  -> 2 ZOO * 15% = 0.3 ZooToken
      expect(afterBalance).to.eq(beforeBalance.add(THOUSANDTH_ZOO.mul(300)))
    })

    it('should pay the curator', async () => {
      const beforeBalance = await ethers.provider.getBalance(curatorAddress)
      await run()
      const afterBalance = await ethers.provider.getBalance(curatorAddress)

      // 20% of 1.7 ZooToken -> 0.34
      expect(smallify(afterBalance)).to.be.approximately(smallify(beforeBalance.add(THOUSANDTH_ZOO.mul(340))), smallify(TENTH_ZOO))
    })
  })

  describe('ZooToken Auction with no curator', () => {
    async function run() {
      await media.connect(owner).approve(auction.address, 0)
      await auction.connect(owner).createAuction(0, media.address, ONE_DAY, TENTH_ZOO, ethers.constants.AddressZero, 20, token.address)
      // await token.connect(bidderA).deposit({ value: ONE_ZOO });
      await token.connect(bidderA).approve(auction.address, ONE_ZOO)
      // await token.connect(bidderB).deposit({ value: TWO_ZOO });
      await token.connect(bidderB).approve(auction.address, TWO_ZOO)
      await auction.connect(bidderA).createBid(0, ONE_ZOO, { value: ONE_ZOO })
      await auction.connect(bidderB).createBid(0, TWO_ZOO, { value: TWO_ZOO })
      await ethers.provider.send('evm_setNextBlockTimestamp', [Date.now() + ONE_DAY])
      await auction.connect(otherUser).endAuction(0)
    }

    it('should transfer the NFT to the winning bidder', async () => {
      await run()
      expect(await media.ownerOf(0)).to.eq(bidderBAddress)
    })

    it('should withdraw the winning bid amount from the winning bidder', async () => {
      await run()
      const afterBalance = await token.balanceOf(bidderBAddress)

      expect(afterBalance).to.eq(ONE_ZOO.mul(0))
    })

    it('should refund the losing bidder', async () => {
      await run()
      const afterBalance = await token.balanceOf(bidderAAddress)

      expect(afterBalance).to.eq(ONE_ZOO)
    })

    it('should pay the auction creator', async () => {
      await run()
      const afterBalance = await token.balanceOf(ownerAddress)

      // 15% creator fee -> 2 ZOO * 85% = 1.7ZooToken
      expect(afterBalance).to.eq(TENTH_ZOO.mul(17))
    })

    it('should pay the token creator', async () => {
      const beforeBalance = await token.balanceOf(creatorAddress)
      await run()
      const afterBalance = await token.balanceOf(creatorAddress)

      // 15% creator fee -> 2 ZOO * 15% = 0.3 ZooToken
      expect(afterBalance).to.eq(beforeBalance.add(THOUSANDTH_ZOO.mul(300)))
    })
  })

  describe('ZooToken auction with curator', async () => {
    async function run() {
      await media.connect(owner).approve(auction.address, 0)
      await auction.connect(owner).createAuction(0, media.address, ONE_DAY, TENTH_ZOO, curator.address, 20, token.address)
      await auction.connect(curator).setAuctionApproval(0, true)
      // await token.connect(bidderA).deposit({ value: ONE_ZOO });
      await token.connect(bidderA).approve(auction.address, ONE_ZOO)
      // await token.connect(bidderB).deposit({ value: TWO_ZOO });
      await token.connect(bidderB).approve(auction.address, TWO_ZOO)
      await auction.connect(bidderA).createBid(0, ONE_ZOO, { value: ONE_ZOO })
      await auction.connect(bidderB).createBid(0, TWO_ZOO, { value: TWO_ZOO })
      await ethers.provider.send('evm_setNextBlockTimestamp', [Date.now() + ONE_DAY])
      await auction.connect(otherUser).endAuction(0)
    }

    it('should transfer the NFT to the winning bidder', async () => {
      await run()
      expect(await media.ownerOf(0)).to.eq(bidderBAddress)
    })

    it('should withdraw the winning bid amount from the winning bidder', async () => {
      await run()
      const afterBalance = await token.balanceOf(bidderBAddress)

      expect(afterBalance).to.eq(ONE_ZOO.mul(0))
    })

    it('should refund the losing bidder', async () => {
      await run()
      const afterBalance = await token.balanceOf(bidderAAddress)

      expect(afterBalance).to.eq(ONE_ZOO)
    })

    it('should pay the auction creator', async () => {
      await run()
      const afterBalance = await token.balanceOf(ownerAddress)

      // 15% creator fee + 20% curator fee -> 2 ZOO * 85% * 80% = 1.36ZooToken
      expect(afterBalance).to.eq(THOUSANDTH_ZOO.mul(1360))
    })

    it('should pay the token creator', async () => {
      const beforeBalance = await token.balanceOf(creatorAddress)
      await run()
      const afterBalance = await token.balanceOf(creatorAddress)

      // 15% creator fee -> 2 ZOO * 15% = 0.3 ZooToken
      expect(afterBalance).to.eq(beforeBalance.add(THOUSANDTH_ZOO.mul(300)))
    })

    it('should pay the auction curator', async () => {
      const beforeBalance = await token.balanceOf(curatorAddress)
      await run()
      const afterBalance = await token.balanceOf(curatorAddress)

      // 15% creator fee + 20% curator fee = 2 ZOO * 85% * 20% = 0.34 ZooToken
      expect(afterBalance).to.eq(beforeBalance.add(THOUSANDTH_ZOO.mul(340)))
    })
  })

  describe('3rd party nft auction', async () => {
    async function run() {
      await otherNft.connect(owner).approve(auction.address, 0)
      await auction.connect(owner).createAuction(0, otherNft.address, ONE_DAY, TENTH_ZOO, curatorAddress, 20, ethers.constants.AddressZero)
      await auction.connect(curator).setAuctionApproval(0, true)
      await auction.connect(bidderA).createBid(0, ONE_ZOO, { value: ONE_ZOO })
      await auction.connect(bidderB).createBid(0, TWO_ZOO, { value: TWO_ZOO })
      await ethers.provider.send('evm_setNextBlockTimestamp', [Date.now() + ONE_DAY])
      await auction.connect(otherUser).endAuction(0)
    }
    it('should transfer the NFT to the winning bidder', async () => {
      await run()
      expect(await otherNft.ownerOf(0)).to.eq(bidderBAddress)
    })

    it('should withdraw the winning bid amount from the winning bidder', async () => {
      const beforeBalance = await ethers.provider.getBalance(bidderBAddress)
      await run()
      const afterBalance = await ethers.provider.getBalance(bidderBAddress)

      expect(smallify(beforeBalance.sub(afterBalance))).to.be.approximately(smallify(TWO_ZOO), smallify(TENTH_ZOO))
    })

    it('should refund the losing bidder', async () => {
      const beforeBalance = await ethers.provider.getBalance(bidderAAddress)
      await run()
      const afterBalance = await ethers.provider.getBalance(bidderAAddress)

      expect(smallify(beforeBalance)).to.be.approximately(smallify(afterBalance), smallify(TENTH_ZOO))
    })

    it('should pay the auction creator', async () => {
      const beforeBalance = await ethers.provider.getBalance(ownerAddress)
      await run()
      const afterBalance = await ethers.provider.getBalance(ownerAddress)

      expect(smallify(afterBalance)).to.be.approximately(
        // 20% curator fee  -> 2 ZOO * 80% = 1.6 ZOO
        smallify(beforeBalance.add(TENTH_ZOO.mul(16))),
        smallify(TENTH_ZOO),
      )
    })

    it('should pay the curator', async () => {
      const beforeBalance = await ethers.provider.getBalance(curatorAddress)
      await run()
      const afterBalance = await ethers.provider.getBalance(curatorAddress)

      // 20% of 2 ZooToken -> 0.4
      expect(smallify(afterBalance)).to.be.approximately(smallify(beforeBalance.add(TENTH_ZOO.mul(4))), smallify(THOUSANDTH_ZOO))
    })
  })
})
