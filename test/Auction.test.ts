import chai, { expect } from 'chai'
import asPromised from 'chai-as-promised'
// @ts-ignore
import { ethers } from 'hardhat'
import { Auction, Market, Media, BadBidder, TestERC721, BadERC721 } from '../types'
import { formatUnits } from 'ethers/lib/utils'
import { BigNumber, Contract, Signer } from 'ethers'
import { approveAuction, deployBidder, deployOtherNFTs, deployToken, deployProtocol, mint, ONE_ZOO, revert, TWO_ZOO } from './utils'

import { solidity } from 'ethereum-waffle'

chai.use(solidity)

chai.use(asPromised)

describe.skip('Auction', () => {
  let market: Market
  let media: Media
  let token: Contract
  let badERC721: BadERC721
  let testERC721: TestERC721

  beforeEach(async () => {
    const signers = await ethers.getSigners()

    await ethers.provider.send('hardhat_reset', [])
    token = await deployToken()
    const contracts = await deployProtocol(token.address)
    const nfts = await deployOtherNFTs()
    market = contracts.market
    media = contracts.media
    badERC721 = nfts.bad
    testERC721 = nfts.test

    for (var i = 0; i < signers.length; i++) {
      await token.mint(signers[i].address, 10000000000)
    }
  })

  async function deploy(): Promise<Auction> {
    const Auction = await ethers.getContractFactory('Auction')
    const auctionHouse = await Auction.deploy()
    auctionHouse.configure(media.address, token.address)
    return auctionHouse as Auction
  }

  async function createAuction(auctionHouse: Auction, curator: string, currency = token.address) {
    const tokenId = 0
    const duration = 60 * 60 * 24
    const reservePrice = 100

    await auctionHouse.createAuction(tokenId, media.address, duration, reservePrice, curator, 5, currency)
  }

  describe('#constructor', () => {
    it('should be able to deploy', async () => {
      const Auction = await ethers.getContractFactory('Auction')
      const auctionHouse = await Auction.deploy()
      await auctionHouse.configure(media.address, token.address)

      expect(await auctionHouse.mediaAddress()).to.eq(media.address, 'incorrect Media address')
      expect(formatUnits(await auctionHouse.timeBuffer(), 0)).to.eq('900', 'time buffer should equal 900')
      expect(await auctionHouse.minBidIncrementPercentage()).to.eq(5, 'minBidIncrementPercentage should equal 5%')
    })

    it('should not allow a configuration address that is not the Zora Media Protocol', async () => {
      const Auction = await ethers.getContractFactory('Auction')
      const zooAuction = await Auction.deploy()
      await expect(zooAuction.configure('0x0000000000000000000000000000000000000000', token.address)).to.be.reverted
    })
  })

  describe('#createAuction', () => {
    let auctionHouse: Auction
    beforeEach(async () => {
      auctionHouse = await deploy()
      await mint(media)
      await approveAuction(media, auctionHouse)
    })

    it('should revert if the token contract does not support the ERC721 interface', async () => {
      const duration = 60 * 60 * 24
      const reservePrice = 100

      const [_, curator] = await ethers.getSigners()

      await expect(auctionHouse.createAuction(0, badERC721.address, duration, reservePrice, curator.address, 5, '0x0000000000000000000000000000000000000000')).to.be.revertedWith(
        'tokenContract does not support ERC721 interface',
      )
    })

    it('should revert if the caller is not approved', async () => {
      const duration = 60 * 60 * 24
      const reservePrice = 100
      const [_, curator, __, ___, unapproved] = await ethers.getSigners()
      await expect(
        auctionHouse.connect(unapproved).createAuction(0, media.address, duration, reservePrice, curator.address, 5, '0x0000000000000000000000000000000000000000'),
      ).to.be.revertedWith('Caller must be approved or owner for token id')
    })

    it('should revert if the token ID does not exist', async () => {
      const tokenId = 999
      const duration = 60 * 60 * 24
      const reservePrice = 100
      const owner = await media.ownerOf(0)
      const [admin, curator] = await ethers.getSigners()

      await expect(
        auctionHouse.connect(admin).createAuction(tokenId, media.address, duration, reservePrice, curator.address, 5, '0x0000000000000000000000000000000000000000'),
      ).to.be.revertedWith('ERC721: owner query for nonexistent token')
    })

    it('should revert if the curator fee percentage is >= 100', async () => {
      const duration = 60 * 60 * 24
      const reservePrice = 100
      const owner = await media.ownerOf(0)
      const [_, curator] = await ethers.getSigners()

      await expect(auctionHouse.createAuction(0, media.address, duration, reservePrice, curator.address, 100, '0x0000000000000000000000000000000000000000')).to.be.revertedWith(
        'curatorFeePercentage must be less than 100',
      )
    })

    it('should create an auction', async () => {
      const owner = await media.ownerOf(0)
      const [_, expectedCurator] = await ethers.getSigners()
      await createAuction(auctionHouse, await expectedCurator.getAddress())

      const createdAuction = await auctionHouse.auctions(0)

      expect(createdAuction.duration).to.eq(24 * 60 * 60)
      expect(createdAuction.reservePrice).to.eq(100)
      expect(createdAuction.curatorFeePercentage).to.eq(5)
      expect(createdAuction.tokenOwner).to.eq(owner)
      expect(createdAuction.curator).to.eq(expectedCurator.address)
      expect(createdAuction.approved).to.eq(false)
    })

    it('should be automatically approved if the creator is the curator', async () => {
      const owner = await media.ownerOf(0)
      await createAuction(auctionHouse, owner)

      const createdAuction = await auctionHouse.auctions(0)

      expect(createdAuction.approved).to.eq(true)
    })

    it('should be automatically approved if the creator is the Zero Address', async () => {
      await createAuction(auctionHouse, ethers.constants.AddressZero)

      const createdAuction = await auctionHouse.auctions(0)

      expect(createdAuction.approved).to.eq(true)
    })

    it('should emit an AuctionCreated event', async () => {
      const owner = await media.ownerOf(0)
      const [_, expectedCurator] = await ethers.getSigners()

      const block = await ethers.provider.getBlockNumber()
      await createAuction(auctionHouse, await expectedCurator.getAddress())
      const currAuction = await auctionHouse.auctions(0)
      const events = await auctionHouse.queryFilter(auctionHouse.filters.AuctionCreated(null, null, null, null, null, null, null, null, null), block)
      expect(events.length).eq(1)
      const logDescription = auctionHouse.interface.parseLog(events[0])
      expect(logDescription.name).to.eq('AuctionCreated')
      expect(logDescription.args.duration).to.eq(currAuction.duration)
      expect(logDescription.args.reservePrice).to.eq(currAuction.reservePrice)
      expect(logDescription.args.tokenOwner).to.eq(currAuction.tokenOwner)
      expect(logDescription.args.curator).to.eq(currAuction.curator)
      expect(logDescription.args.curatorFeePercentage).to.eq(currAuction.curatorFeePercentage)
      expect(logDescription.args.auctionCurrency).to.eq(token.address)
    })
  })

  describe('#setAuctionApproval', () => {
    let auctionHouse: Auction
    let admin: Signer
    let curator: Signer
    let bidder: Signer

    beforeEach(async () => {
      ;[admin, curator, bidder] = await ethers.getSigners()
      auctionHouse = (await deploy()).connect(curator) as Auction
      await mint(media)
      await approveAuction(media, auctionHouse)
      await createAuction(auctionHouse.connect(admin), await curator.getAddress())
    })

    it('should revert if the auctionHouse does not exist', async () => {
      await expect(auctionHouse.setAuctionApproval(1, true)).to.be.revertedWith("Auction doesn't exist")
    })

    it('should revert if not called by the curator', async () => {
      await expect(auctionHouse.connect(admin).setAuctionApproval(0, true)).to.be.revertedWith('Must be auction curator')
    })

    it('should revert if the auction has already started', async () => {
      token = token.connect(bidder)

      await token.approve(auctionHouse.address, 100)

      await auctionHouse.setAuctionApproval(0, true)

      await auctionHouse.connect(bidder).createBid(0, 100)

      await expect(auctionHouse.setAuctionApproval(0, false)).to.be.revertedWith('Auction has already started')
    })

    it('should set the auction as approved', async () => {
      await auctionHouse.setAuctionApproval(0, true)

      expect((await auctionHouse.auctions(0)).approved).to.eq(true)
    })

    it('should emit an AuctionApproved event', async () => {
      const block = await ethers.provider.getBlockNumber()
      await auctionHouse.setAuctionApproval(0, true)
      const events = await auctionHouse.queryFilter(auctionHouse.filters.AuctionApprovalUpdated(null, null, null, null), block)
      expect(events.length).eq(1)
      const logDescription = auctionHouse.interface.parseLog(events[0])

      expect(logDescription.args.approved).to.eq(true)
    })
  })

  describe('#setAuctionReservePrice', () => {
    let auctionHouse: Auction
    let admin: Signer
    let creator: Signer
    let curator: Signer
    let bidder: Signer

    beforeEach(async () => {
      ;[admin, creator, curator, bidder] = await ethers.getSigners()
      auctionHouse = (await deploy()).connect(curator) as Auction
      await mint(media.connect(creator))
      await approveAuction(media.connect(creator), auctionHouse.connect(creator))
      await createAuction(auctionHouse.connect(creator), await curator.getAddress())
    })

    it('should revert if the auctionHouse does not exist', async () => {
      await expect(auctionHouse.setAuctionReservePrice(1, TWO_ZOO)).to.be.revertedWith("Auction doesn't exist")
    })

    it('should revert if not called by the curator or owner', async () => {
      await expect(auctionHouse.connect(admin).setAuctionReservePrice(0, TWO_ZOO)).to.be.revertedWith('Must be auction curator or token owner')
    })

    it('should revert if the auction has already started', async () => {
      token = token.connect(bidder)

      await token.approve(auctionHouse.address, 200)

      await auctionHouse.setAuctionReservePrice(0, 200)

      await auctionHouse.setAuctionApproval(0, true)

      await auctionHouse.connect(bidder).createBid(0, 200, { value: 200 })

      await expect(auctionHouse.setAuctionReservePrice(0, 200)).to.be.revertedWith('Auction has already started')
    })

    it('should set the auction reserve price when called by the curator', async () => {
      await auctionHouse.setAuctionReservePrice(0, TWO_ZOO)

      expect((await auctionHouse.auctions(0)).reservePrice).to.eq(TWO_ZOO)
    })

    it('should set the auction reserve price when called by the token owner', async () => {
      await auctionHouse.connect(creator).setAuctionReservePrice(0, TWO_ZOO)

      expect((await auctionHouse.auctions(0)).reservePrice).to.eq(TWO_ZOO)
    })

    it('should emit an AuctionReservePriceUpdated event', async () => {
      const block = await ethers.provider.getBlockNumber()
      await auctionHouse.setAuctionReservePrice(0, TWO_ZOO)
      const events = await auctionHouse.queryFilter(auctionHouse.filters.AuctionReservePriceUpdated(null, null, null, null), block)
      expect(events.length).eq(1)
      const logDescription = auctionHouse.interface.parseLog(events[0])

      expect(logDescription.args.reservePrice).to.eq(TWO_ZOO)
    })
  })

  describe('#createBid', () => {
    let auctionHouse: Auction
    let admin: Signer
    let curator: Signer
    let bidderA: Signer
    let bidderB: Signer

    beforeEach(async () => {
      ;[admin, curator, bidderA, bidderB] = await ethers.getSigners()
      auctionHouse = (await (await deploy()).connect(bidderA).deployed()) as Auction
      await mint(media)
      await approveAuction(media, auctionHouse)
      await createAuction(auctionHouse.connect(admin), await curator.getAddress())
      await auctionHouse.connect(curator).setAuctionApproval(0, true)
    })

    it('should revert if the specified auction does not exist', async () => {
      await expect(auctionHouse.createBid(11111, 200)).to.be.revertedWith("Auction doesn't exist")
    })

    it('should revert if the specified auction is not approved', async () => {
      await auctionHouse.connect(curator).setAuctionApproval(0, false)
      await expect(auctionHouse.createBid(0, 200, { value: 200 })).to.be.revertedWith('Auction must be approved by curator')
    })

    it('should revert if the bid is less than the reserve price', async () => {
      await expect(auctionHouse.createBid(0, 0, { value: 0 })).to.be.revertedWith('Must send at least reservePrice')
    })

    describe('#first bid', () => {
      it('should set the first bid time', async () => {
        token = token.connect(auctionHouse.signer)

        await token.approve(auctionHouse.address, 200)

        await ethers.provider.send('evm_setNextBlockTimestamp', [9617249934])

        await auctionHouse.createBid(0, 100, {
          value: 100,
        })

        expect((await auctionHouse.auctions(0)).firstBidTime).to.eq(9617249934)
      })

      it('should store the transferred ZOO', async () => {
        token = token.connect(auctionHouse.signer)

        await token.approve(auctionHouse.address, 200)

        await auctionHouse.createBid(0, 200)

        const balanceAfterBid = await token.balanceOf(auctionHouse.address)

        expect(balanceAfterBid).to.eq(200)
      })

      it("should not update the auction's duration", async () => {
        token = token.connect(auctionHouse.signer)

        await token.approve(auctionHouse.address, 200)

        const beforeDuration = (await auctionHouse.auctions(0)).duration

        await auctionHouse.createBid(0, 200)

        const afterDuration = (await auctionHouse.auctions(0)).duration

        expect(beforeDuration).to.eq(afterDuration)
      })

      it("should store the bidder's information", async () => {
        token = token.connect(auctionHouse.signer)

        await token.approve(auctionHouse.address, 200)

        await auctionHouse.createBid(0, 200)

        const currAuction = await auctionHouse.auctions(0)

        expect(currAuction.bidder).to.eq(await bidderA.getAddress())

        expect(currAuction.amount).to.eq(200)
      })

      it('should emit an AuctionBid event', async () => {
        const block = await ethers.provider.getBlockNumber()

        token = token.connect(auctionHouse.signer)

        await token.connect(admin).mint(await auctionHouse.signer.getAddress(), 200)
        await token.approve(auctionHouse.address, 200)

        await auctionHouse.createBid(0, 200, {
          value: 200,
        })
        const events = await auctionHouse.queryFilter(auctionHouse.filters.AuctionBid(null, null, null, null, null, null, null), block)
        expect(events.length).eq(1)
        const logDescription = auctionHouse.interface.parseLog(events[0])

        expect(logDescription.name).to.eq('AuctionBid')
        expect(logDescription.args.auctionId).to.eq(0)
        expect(logDescription.args.sender).to.eq(await bidderA.getAddress())
        expect(logDescription.args.value).to.eq(200)
        expect(logDescription.args.firstBid).to.eq(true)
        expect(logDescription.args.extended).to.eq(false)
      })
    })

    describe('#second bid', () => {
      beforeEach(async () => {
        token = token.connect(bidderA)

        await token.approve(auctionHouse.address, 300)

        auctionHouse = auctionHouse.connect(bidderB) as Auction

        await auctionHouse.connect(bidderA).createBid(0, 200, { value: 200 })
      })

      it('should revert if the bid is smaller than the last bid + minBid', async () => {
        await expect(
          auctionHouse.createBid(0, 202, {
            value: 202,
          }),
        ).to.be.revertedWith('Must send more than last bid by minBidIncrementPercentage amount')
      })

      it('should refund the previous bid', async () => {
        token = token.connect(auctionHouse.signer)

        await token.approve(auctionHouse.address, 300)

        const beforeBalance = await ethers.provider.getBalance(await bidderA.getAddress())

        const beforeBidAmount = (await auctionHouse.auctions(0)).amount
        await auctionHouse.createBid(0, 250, {
          value: 250,
        })

        const afterBalance = await ethers.provider.getBalance(await bidderA.getAddress())

        expect(afterBalance).to.eq(beforeBalance)
      })

      it('should not update the firstBidTime', async () => {
        token = token.connect(auctionHouse.signer)

        await token.approve(auctionHouse.address, 500)

        const firstBidTime = (await auctionHouse.auctions(0)).firstBidTime

        await auctionHouse.createBid(0, 300, {
          value: 300,
        })

        expect((await auctionHouse.auctions(0)).firstBidTime).to.eq(firstBidTime)
      })

      it('should transfer the bid to the contract and store it as ZOO', async () => {
        token = token.connect(auctionHouse.signer)

        await token.approve(auctionHouse.address, 500)

        await auctionHouse.createBid(0, 300, {
          value: 300,
        })

        expect(await token.balanceOf(auctionHouse.address)).to.eq(300)
      })

      it('should update the stored bid information', async () => {
        token = token.connect(auctionHouse.signer)

        await token.approve(auctionHouse.address, 500)

        await auctionHouse.createBid(0, 300, {
          value: 300,
        })

        const currAuction = await auctionHouse.auctions(0)

        expect(currAuction.amount).to.eq(300)
        expect(currAuction.bidder).to.eq(await bidderB.getAddress())
      })

      it('should not extend the duration of the bid if outside of the time buffer', async () => {
        token = token.connect(auctionHouse.signer)

        await token.approve(auctionHouse.address, 500)

        const beforeDuration = (await auctionHouse.auctions(0)).duration

        await auctionHouse.createBid(0, 300, {
          value: 300,
        })

        const afterDuration = (await auctionHouse.auctions(0)).duration

        expect(beforeDuration).to.eq(afterDuration)
      })

      it('should emit an AuctionBid event', async () => {
        token = token.connect(auctionHouse.signer)

        await token.approve(auctionHouse.address, 500)

        const block = await ethers.provider.getBlockNumber()

        const createBidTx = await auctionHouse.createBid(0, 300, {
          value: 300,
        })

        const createBidReceipt = await createBidTx.wait()

        expect(createBidReceipt.events[3].event).to.eq('AuctionBid')

        expect(createBidReceipt.events[3].args.sender).to.eq(await bidderB.getAddress())

        expect(parseInt(createBidReceipt.events[3].args.value._hex)).to.eq(300)

        expect(createBidReceipt.events[3].args.firstBid).to.eq(false)

        expect(createBidReceipt.events[3].args.extended).to.eq(false)
      })

      describe('last minute bid', () => {
        beforeEach(async () => {
          await token.connect(bidderA).approve(auctionHouse.address, 2000)
          const currAuction = await auctionHouse.auctions(0)
          await ethers.provider.send('evm_setNextBlockTimestamp', [currAuction.firstBidTime.add(currAuction.duration).sub(10).toNumber()])
        })

        it('should extend the duration of the bid if inside of the time buffer', async () => {
          const beforeDuration = (await auctionHouse.auctions(0)).duration
          await auctionHouse.connect(bidderA).createBid(0, 500)

          const currAuction = await auctionHouse.auctions(0)
          expect(currAuction.duration).to.eq(beforeDuration.add(await auctionHouse.timeBuffer()).sub(10))
        })

        it('should emit an AuctionBid event', async () => {
          const block = await ethers.provider.getBlockNumber()
          await token.connect(admin).mint(await auctionHouse.signer.getAddress(), TWO_ZOO)
          await token.connect(auctionHouse.signer).approve(auctionHouse.address, TWO_ZOO)
          await auctionHouse.createBid(0, TWO_ZOO)
          const events = await auctionHouse.queryFilter(auctionHouse.filters.AuctionBid(0, null, null, null, null, null, null), block)
          expect(events.length).eq(1)
          const logDescription = auctionHouse.interface.parseLog(events[0])

          expect(logDescription.name).to.eq('AuctionBid')
          expect(logDescription.args.sender).to.eq(await bidderB.getAddress())
          expect(logDescription.args.value).to.eq(TWO_ZOO)
          expect(logDescription.args.firstBid).to.eq(false)
          expect(logDescription.args.extended).to.eq(true)
        })

        describe('late bid', () => {
          beforeEach(async () => {
            const currAuction = await auctionHouse.auctions(0)
            await ethers.provider.send('evm_setNextBlockTimestamp', [currAuction.firstBidTime.add(currAuction.duration).sub(5).toNumber()])
          })

          it('should emit an AuctionBid event', async () => {
            token = token.connect(auctionHouse.signer)

            await token.connect(admin).mint(await auctionHouse.signer.getAddress(), 300)
            await token.approve(auctionHouse.address, 300)

            const block = await ethers.provider.getBlockNumber()

            await auctionHouse.createBid(0, 210)

            const events = await auctionHouse.queryFilter(auctionHouse.filters.AuctionBid(null, null, null, null, null, null), block)
            expect(events.length).eq(1)
            const logDescription = auctionHouse.interface.parseLog(events[0])

            expect(logDescription.name).to.eq('AuctionBid')
            expect(logDescription.args.sender).to.eq(await bidderB.getAddress())
            expect(logDescription.args.value).to.eq(210)
            expect(logDescription.args.firstBid).to.eq(false)
            expect(logDescription.args.extended).to.eq(true)
          })
        })

        describe('late bid', () => {
          beforeEach(async () => {
            const currAuction = await auctionHouse.auctions(0)
            await ethers.provider.send('evm_setNextBlockTimestamp', [currAuction.firstBidTime.add(currAuction.duration).add(1).toNumber()])
          })

          it('should revert if the bid is placed after expiry', async () => {
            await expect(auctionHouse.createBid(0, 200, { value: 200 })).to.be.revertedWith('Auction expired')
          })
        })
      })
    })

    describe('#cancelAuction', () => {
      // let auctionHouse: Auction;
      let admin: Signer
      let creator: Signer
      let curator: Signer
      let bidder: Signer
      let bidder2: Signer

      beforeEach(async () => {
        ;[admin, curator, bidder, bidder2] = await ethers.getSigners()
      })

      it('should revert if the auction does not exist', async () => {
        await expect(auctionHouse.cancelAuction(2)).eventually.rejectedWith(`\'Auction doesn\'t exist\'`)
      })

      it('should revert if not called by a creator or curator', async () => {
        await expect(auctionHouse.connect(bidder).cancelAuction(0)).to.be.revertedWith('Can only be called by auction creator or curator')
      })

      it('should revert if not called by a creator or curator', async () => {
        await expect(auctionHouse.connect(bidder).cancelAuction(0)).eventually.rejectedWith(`Can only be called by auction creator or curator`)
      })

      it('should revert if the auction has already begun', async () => {
        await token.connect(bidder).approve(auctionHouse.address, 200)
        await auctionHouse.connect(bidder).createBid(0, 200, { value: 200 })
        await expect(auctionHouse.connect(admin).cancelAuction(0)).eventually.rejectedWith(`Can't cancel an auction once it's begun`)
      })

      it('should be callable by the creator', async () => {
        // The admin is the "creator" of the auction
        await auctionHouse.connect(admin).cancelAuction(0)

        const auctionResult = await auctionHouse.auctions(0)

        expect(auctionResult.amount.toNumber()).to.eq(0)
        expect(auctionResult.duration.toNumber()).to.eq(0)
        expect(auctionResult.firstBidTime.toNumber()).to.eq(0)
        expect(auctionResult.reservePrice.toNumber()).to.eq(0)
        expect(auctionResult.curatorFeePercentage).to.eq(0)
        expect(auctionResult.tokenOwner).to.eq(ethers.constants.AddressZero)
        expect(auctionResult.bidder).to.eq(ethers.constants.AddressZero)
        expect(auctionResult.curator).to.eq(ethers.constants.AddressZero)
        expect(auctionResult.auctionCurrency).to.eq(ethers.constants.AddressZero)

        expect(await media.ownerOf(0)).to.eq(await admin.getAddress())
      })

      it('should be callable by the curator', async () => {
        await auctionHouse.connect(curator).cancelAuction(0)

        const auctionResult = await auctionHouse.auctions(0)

        expect(auctionResult.amount.toNumber()).to.eq(0)
        expect(auctionResult.duration.toNumber()).to.eq(0)
        expect(auctionResult.firstBidTime.toNumber()).to.eq(0)
        expect(auctionResult.reservePrice.toNumber()).to.eq(0)
        expect(auctionResult.curatorFeePercentage).to.eq(0)
        expect(auctionResult.tokenOwner).to.eq(ethers.constants.AddressZero)
        expect(auctionResult.bidder).to.eq(ethers.constants.AddressZero)
        expect(auctionResult.curator).to.eq(ethers.constants.AddressZero)
        expect(auctionResult.auctionCurrency).to.eq(ethers.constants.AddressZero)
        expect(await media.ownerOf(0)).to.eq(await admin.getAddress())
      })

      it('should emit an AuctionCanceled event', async () => {
        const block = await ethers.provider.getBlockNumber()

        await auctionHouse.connect(admin).cancelAuction(0)

        const events = await auctionHouse.queryFilter(auctionHouse.filters.AuctionCanceled(null, null, null, null), block)

        expect(events.length).eq(1)

        const logDescription = auctionHouse.interface.parseLog(events[0])

        expect(logDescription.args.tokenId.toNumber()).to.eq(0)

        expect(logDescription.args.tokenOwner).to.eq(await admin.getAddress())

        expect(logDescription.args.tokenContract).to.eq(media.address)
      })
    })

    describe('#endAuction', () => {
      let admin: Signer
      let creator: Signer
      let curator: Signer
      let bidder: Signer
      let other: Signer
      let badBidder: BadBidder

      beforeEach(async () => {
        ;[admin, creator, curator, bidder, other] = await ethers.getSigners()
      })

      it('should revert if the auction does not exist', async () => {
        await expect(auctionHouse.endAuction(1110)).to.be.revertedWith("Auction doesn't exist")
      })

      it('should revert if the auction has not begun', async () => {
        await expect(auctionHouse.endAuction(0)).to.be.revertedWith("Auction hasn't begun")
      })

      it('should revert if the auction has not completed', async () => {
        token = token.connect(auctionHouse.signer)

        await token.approve(auctionHouse.address, 200)

        await auctionHouse.createBid(0, 200, {
          value: 200,
        })

        await expect(auctionHouse.endAuction(0)).to.be.revertedWith("Auction hasn't completed")
      })

      it('should cancel the auction if the winning bidder is unable to receive NFTs', async () => {
        let badBidderFactory = await ethers.getContractFactory('BadBidder')
        badBidder = (await badBidderFactory.deploy(auctionHouse.address, token.address)) as any

        token = token.connect(admin)
        await token.mint(badBidder.address, TWO_ZOO)
        await badBidder.approve(auctionHouse.address, 500)
        let badBalance: BigNumber
        badBalance = await token.balanceOf(badBidder.address)
        await badBidder.placeBid(0, 500)
        const endTime = (await auctionHouse.auctions(0)).duration.toNumber() + (await auctionHouse.auctions(0)).firstBidTime.toNumber()
        await ethers.provider.send('evm_setNextBlockTimestamp', [endTime + 1])

        await auctionHouse.endAuction(0)

        expect(await media.ownerOf(0)).to.eq(await admin.getAddress())
        expect(await token.balanceOf(badBidder.address)).to.eq(TWO_ZOO)
      })

      describe('ZOO auction', () => {
        beforeEach(async () => {
          token = token.connect(auctionHouse.signer)

          token.connect(admin).mint(await bidderA.getAddress(), TWO_ZOO)
          await token.approve(auctionHouse.address, TWO_ZOO)

          await auctionHouse.connect(bidderA).createBid(0, TWO_ZOO)

          const endTime = (await auctionHouse.auctions(0)).duration.toNumber() + (await auctionHouse.auctions(0)).firstBidTime.toNumber()
          await ethers.provider.send('evm_setNextBlockTimestamp', [endTime + 1])
        })

        it('should transfer the NFT to the winning bidder', async () => {
          await auctionHouse.endAuction(0)

          expect(await media.ownerOf(0)).to.eq(await bidderA.getAddress())
        })

        it('should pay the curator their curatorFee percentage', async () => {
          const beforeBalance = await token.balanceOf(await creator.getAddress())
          await auctionHouse.endAuction(0)

          const expectedCuratorFee = '100000000000000000' // 0.05 * 2000000000000000000

          const curatorBalance = await token.balanceOf(await creator.getAddress())
          expect(curatorBalance.sub(beforeBalance).toString()).to.eq(expectedCuratorFee)
        })

        it('should pay the creator the remainder of the winning bid', async () => {
          const beforeBalance = await ethers.provider.getBalance(await creator.getAddress())

          await auctionHouse.endAuction(0)

          const expectedProfit = '100000010000000000'

          const creatorBalance = await ethers.provider.getBalance(await creator.getAddress())

          const tokenBalance = await token.balanceOf(await creator.getAddress())

          await expect(creatorBalance.sub(beforeBalance).add(tokenBalance).toString()).to.eq(expectedProfit)
        })

        it('should emit an AuctionEnded event', async () => {
          const block = await ethers.provider.getBlockNumber()
          const auctionData = await auctionHouse.auctions(0)
          await auctionHouse.endAuction(0)
          const events = await auctionHouse.queryFilter(auctionHouse.filters.AuctionEnded(null, null, null, null, null, null, null, null, null), block)
          expect(events.length).eq(1)
          const logDescription = auctionHouse.interface.parseLog(events[0])

          expect(logDescription.args.tokenId).to.eq(0)
          expect(logDescription.args.tokenOwner).to.eq(auctionData.tokenOwner)
          expect(logDescription.args.curator).to.eq(auctionData.curator)
          expect(logDescription.args.winner).to.eq(auctionData.bidder)
          expect(logDescription.args.amount.toString()).to.eq('1900000000000000000')
          expect(logDescription.args.curatorFee.toString()).to.eq('100000000000000000')
          expect(logDescription.args.auctionCurrency).to.eq(token.address)
        })

        it('should delete the auction', async () => {
          await auctionHouse.endAuction(0)

          const auctionResult = await auctionHouse.auctions(0)

          expect(auctionResult.amount.toNumber()).to.eq(0)

          expect(auctionResult.duration.toNumber()).to.eq(0)

          expect(auctionResult.firstBidTime.toNumber()).to.eq(0)

          expect(auctionResult.reservePrice.toNumber()).to.eq(0)

          expect(auctionResult.curatorFeePercentage).to.eq(0)

          expect(auctionResult.tokenOwner).to.eq(ethers.constants.AddressZero)

          expect(auctionResult.bidder).to.eq(ethers.constants.AddressZero)

          expect(auctionResult.curator).to.eq(ethers.constants.AddressZero)

          expect(auctionResult.auctionCurrency).to.eq(ethers.constants.AddressZero)
        })
      })
    })
  })
})
