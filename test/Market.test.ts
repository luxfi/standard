import { ethers } from 'hardhat'
import chai, { expect } from 'chai'
import asPromised from 'chai-as-promised'
chai.use(asPromised)

import { BigNumber, BigNumberish, Wallet } from 'ethers'
import { AddressZero, MaxUint256 } from '@ethersproject/constants'
import { JsonRpcProvider } from '@ethersproject/providers'
import { formatUnits } from '@ethersproject/units'

import Decimal from '../utils/Decimal'
import { Blockchain } from '../utils/Blockchain'
import { generatedWallets } from '../utils/generatedWallets'

import { Market } from '../types/Market'
import { ZOO, Media__factory, Market__factory, ZOO__factory, ZooKeeper__factory } from '../types'

let provider = new JsonRpcProvider()
let blockchain = new Blockchain(provider)

type DecimalValue = { value: BigNumber }

type BidShares = {
  owner: DecimalValue
  prevOwner: DecimalValue
  creator: DecimalValue
}

type Ask = {
  currency: string
  amount: BigNumberish
}

type Bid = {
  currency: string
  amount: BigNumberish
  bidder: string
  recipient: string
  sellOnShare: { value: BigNumberish }
}

describe('Market', () => {
  let [deployerWallet, bidderWallet, mockTokenWallet, otherWallet] = generatedWallets(provider)

  let defaultBidShares = {
    prevOwner: Decimal.new(10),
    owner: Decimal.new(80),
    creator: Decimal.new(10),
  }

  let defaultTokenId = 1
  let defaultAsk = {
    amount: 100,
    currency: '0x41A322b28D0fF354040e2CbC676F0320d8c8850d',
    sellOnShare: Decimal.new(0),
  }

  let marketAddress: string
  let mediaAddress: string
  let tokenAddress: string
  let zookeeperAddress: string

  function toNumWei(val: BigNumber) {
    return parseFloat(formatUnits(val, 'wei'))
  }

  function toNumEther(val: BigNumber) {
    return parseFloat(formatUnits(val, 'ether'))
  }

  async function maketAs(wallet: Wallet) {
    return Market__factory.connect(marketAddress, wallet)
  }

  async function deploy() {
    const token = await (await new ZOO__factory(deployerWallet).deploy()).deployed()
    tokenAddress = token.address

    const market = await (await new Market__factory(deployerWallet).deploy()).deployed()
    marketAddress = market.address

    const media = await (await new Media__factory(deployerWallet).deploy('ZooAnimals', 'ANML')).deployed()
    mediaAddress = media.address

    const zookeeper = await (await new ZooKeeper__factory(deployerWallet).deploy()).deployed()
    zookeeperAddress = zookeeper.address
  }

  async function configure() {
    return Market__factory.connect(marketAddress, deployerWallet).configure(mediaAddress)
  }

  async function readMedia() {
    return Market__factory.connect(marketAddress, deployerWallet).mediaContract()
  }

  async function setBidShares(maket: Market, tokenId: number, bidShares?: BidShares) {
    return maket.setBidShares(tokenId, bidShares)
  }

  async function setAsk(maket: Market, tokenId: number, ask?: Ask) {
    return maket.setAsk(tokenId, ask)
  }

  async function deployCurrency() {
    const currency = await new ZOO__factory(deployerWallet).deploy()
    return {
      address: currency.address,
      contract: currency,
    }
  }

  async function mintCurrency(currency: string, to: string, value: number) {
    await ZOO__factory.connect(currency, deployerWallet).mint(to, value)
  }

  async function approveCurrency(currency: string, spender: string, owner: Wallet) {
    await ZOO__factory.connect(currency, owner).approve(spender, MaxUint256)
  }
  async function getBalance(currency: string, owner: string) {
    return ZOO__factory.connect(currency, deployerWallet).balanceOf(owner)
  }
  async function setBid(maket: Market, bid: Bid, tokenId: number, spender?: string) {
    await maket.setBid(tokenId, bid, spender || bid.bidder, { gasLimit: 3500000 })
  }

  beforeEach(async () => {
    await blockchain.resetAsync()
  })

  describe('#constructor', () => {
    it('should be able to deploy', async () => {
      await expect(deploy()).eventually.fulfilled
    })
  })

  describe('#configure', () => {
    beforeEach(async () => {
      await deploy()
    })

    it('should revert if not called by the owner', async () => {
      await expect(Market__factory.connect(marketAddress, otherWallet).configure(mediaAddress)).eventually.rejectedWith('Market: Only owner')
    })

    it('should be callable by the owner', async () => {
      await expect(configure()).eventually.fulfilled
      const tokenContractAddress = await readMedia()

      expect(tokenContractAddress).eq(mockTokenWallet.address)
    })

    it('should reject if called twice', async () => {
      await configure()

      await expect(configure()).eventually.rejectedWith('Market: Already configured')
    })
  })

  describe('#setBidShares', () => {
    beforeEach(async () => {
      await deploy()
      await configure()
    })

    it('should reject if not called by the media address', async () => {
      const maket = await maketAs(otherWallet)

      await expect(setBidShares(maket, defaultTokenId, defaultBidShares)).rejectedWith('Market: Only media contract')
    })

    it('should set the bid shares if called by the media address', async () => {
      const maket = await maketAs(mockTokenWallet)

      await expect(setBidShares(maket, defaultTokenId, defaultBidShares)).eventually.fulfilled

      const tokenBidShares = Object.values(await maket.bidSharesForToken(defaultTokenId)).map((s) => parseInt(formatUnits(s.value, 'ether')))

      expect(tokenBidShares[0]).eq(toNumEther(defaultBidShares.prevOwner.value))
      expect(tokenBidShares[1]).eq(toNumEther(defaultBidShares.creator.value))
      expect(tokenBidShares[2]).eq(toNumEther(defaultBidShares.owner.value))
    })

    it('should emit an event when bid shares are updated', async () => {
      const maket = await maketAs(mockTokenWallet)

      const block = await provider.getBlockNumber()
      await setBidShares(maket, defaultTokenId, defaultBidShares)
      const events = await maket.queryFilter(maket.filters.BidShareUpdated(null, null), block)
      expect(events.length).eq(1)
      const logDescription = maket.interface.parseLog(events[0])
      expect(toNumWei(logDescription.args.tokenId)).to.eq(defaultTokenId)
      expect(toNumWei(logDescription.args.bidShares.prevOwner.value)).to.eq(toNumWei(defaultBidShares.prevOwner.value))
      expect(toNumWei(logDescription.args.bidShares.creator.value)).to.eq(toNumWei(defaultBidShares.creator.value))
      expect(toNumWei(logDescription.args.bidShares.owner.value)).to.eq(toNumWei(defaultBidShares.owner.value))
    })

    it('should reject if the bid shares are invalid', async () => {
      const maket = await maketAs(mockTokenWallet)
      const invalidBidShares = {
        prevOwner: Decimal.new(0),
        owner: Decimal.new(0),
        creator: Decimal.new(101),
      }

      await expect(setBidShares(maket, defaultTokenId, invalidBidShares)).rejectedWith('Market: Invalid bid shares, must sum to 100')
    })
  })

  describe('#setAsk', () => {
    beforeEach(async () => {
      await deploy()
      await configure()
    })

    it('should reject if not called by the media address', async () => {
      const maket = await maketAs(otherWallet)

      await expect(setAsk(maket, defaultTokenId, defaultAsk)).rejectedWith('Market: Only media contract')
    })

    it('should set the ask if called by the media address', async () => {
      const maket = await maketAs(mockTokenWallet)
      await setBidShares(maket, defaultTokenId, defaultBidShares)

      await expect(setAsk(maket, defaultTokenId, defaultAsk)).eventually.fulfilled

      const ask = await maket.currentAskForToken(defaultTokenId)

      expect(toNumWei(ask.amount)).to.eq(defaultAsk.amount)
      expect(ask.currency).to.eq(defaultAsk.currency)
    })

    it('should emit an event if the ask is updated', async () => {
      const maket = await maketAs(mockTokenWallet)
      await setBidShares(maket, defaultTokenId, defaultBidShares)

      const block = await provider.getBlockNumber()
      await setAsk(maket, defaultTokenId, defaultAsk)
      const events = await maket.queryFilter(maket.filters.AskCreated(null, null), block)

      expect(events.length).eq(1)
      const logDescription = maket.interface.parseLog(events[0])
      expect(toNumWei(logDescription.args.tokenId)).to.eq(defaultTokenId)
      expect(toNumWei(logDescription.args.ask.amount)).to.eq(defaultAsk.amount)
      expect(logDescription.args.ask.currency).to.eq(defaultAsk.currency)
    })

    it('should reject if the ask is too low', async () => {
      const maket = await maketAs(mockTokenWallet)
      await setBidShares(maket, defaultTokenId, defaultBidShares)

      await expect(
        setAsk(maket, defaultTokenId, {
          amount: 1,
          currency: AddressZero,
        }),
      ).rejectedWith('Market: Ask invalid for share splitting')
    })

    it("should reject if the bid shares haven't been set yet", async () => {
      const maket = await maketAs(mockTokenWallet)
      await expect(setAsk(maket, defaultTokenId, defaultAsk)).rejectedWith('Market: Invalid bid shares for token')
    })
  })

  describe('#setBid', () => {
    let currency: string
    const defaultBid = {
      amount: 100,
      currency: currency,
      bidder: bidderWallet.address,
      recipient: otherWallet.address,
      spender: bidderWallet.address,
      sellOnShare: Decimal.new(10),
      contract: null as ZOO,
    }

    beforeEach(async () => {
      await deploy()
      await configure()
      let { address, contract } = await deployCurrency()
      defaultBid.currency = address
      defaultBid.contract = contract
    })

    it('should revert if not called by the media contract', async () => {
      const maket = await maketAs(otherWallet)
      await expect(setBid(maket, defaultBid, defaultTokenId)).rejectedWith('Market: Only media contract')
    })

    it.skip('should revert if the bidder does not have a high enough allowance for their bidding currency', async () => {
      const maket = await maketAs(mockTokenWallet)
      await mintCurrency(defaultBid.currency, defaultBid.bidder, 100000000)
      try {
        await setBid(maket, defaultBid as Bid, defaultTokenId)
      } catch (error) {
        expect(error.body).to.be.equal(
          '{"jsonrpc":"2.0","id":508,"error":{"code":-32603,"message":"Error: VM Exception while processing transaction: revert ERC20: transfer amount exceeds allowance"}}',
        )
      }
    })

    it.skip('should revert if the bidder does not have enough tokens to bid with', async () => {
      const maket = await maketAs(mockTokenWallet)
      await mintCurrency(defaultBid.currency, defaultBid.bidder, defaultBid.amount - 1)
      await approveCurrency(defaultBid.currency, maket.address, bidderWallet)

      try {
        await setBid(maket, defaultBid as Bid, defaultTokenId)
      } catch (error) {
        expect(error.body).to.be.equal(
          '{"jsonrpc":"2.0","id":563,"error":{"code":-32603,"message":"Error: VM Exception while processing transaction: revert ERC20: transfer amount exceeds balance"}}',
        )
      }
    })

    it('should revert if the bid currency is 0 address', async () => {
      const maket = await maketAs(mockTokenWallet)
      await setBidShares(maket, defaultTokenId, defaultBidShares as BidShares)
      await mintCurrency(defaultBid.currency, defaultBid.bidder, defaultBid.amount)
      await approveCurrency(defaultBid.currency, maket.address, bidderWallet)

      await expect(setBid(maket, { ...defaultBid, currency: AddressZero }, defaultTokenId)).rejectedWith('Market: bid currency cannot be 0 address')
    })

    it('should revert if the bid recipient is 0 address', async () => {
      const maket = await maketAs(mockTokenWallet)
      await setBidShares(maket, defaultTokenId, defaultBidShares)
      await mintCurrency(defaultBid.currency, defaultBid.bidder, defaultBid.amount)
      await approveCurrency(defaultBid.currency, maket.address, bidderWallet)

      await expect(setBid(maket, { ...defaultBid, recipient: AddressZero }, defaultTokenId)).rejectedWith('Market: bid recipient cannot be 0 address')
    })

    it('should revert if the bidder bids 0 tokens', async () => {
      const maket = await maketAs(mockTokenWallet)
      await setBidShares(maket, defaultTokenId, defaultBidShares)
      await mintCurrency(defaultBid.currency, defaultBid.bidder, defaultBid.amount)
      await approveCurrency(defaultBid.currency, maket.address, bidderWallet)

      await expect(setBid(maket, { ...defaultBid, amount: 0 }, defaultTokenId)).rejectedWith('Market: cannot bid amount of 0')
    })

    it('should accept a valid bid', async () => {
      const maket = await maketAs(mockTokenWallet)
      await setBidShares(maket, defaultTokenId, defaultBidShares)
      await mintCurrency(defaultBid.currency, defaultBid.bidder, defaultBid.amount)
      await approveCurrency(defaultBid.currency, maket.address, bidderWallet)

      const beforeBalance = toNumWei(await getBalance(defaultBid.currency, defaultBid.bidder))

      await expect(setBid(maket, defaultBid, defaultTokenId)).fulfilled

      const afterBalance = toNumWei(await getBalance(defaultBid.currency, defaultBid.bidder))
      const bid = await maket.bidForTokenBidder(1, bidderWallet.address)
      expect(bid.currency).eq(defaultBid.currency)
      expect(toNumWei(bid.amount)).eq(defaultBid.amount)
      expect(bid.bidder).eq(defaultBid.bidder)
      expect(beforeBalance).eq(afterBalance + defaultBid.amount)
    })

    it('should accept a valid bid larger than the min bid', async () => {
      const maket = await maketAs(mockTokenWallet)
      await setBidShares(maket, defaultTokenId, defaultBidShares)

      const largerValidBid = {
        amount: 130000000,
        currency: defaultBid.currency,
        bidder: bidderWallet.address,
        recipient: otherWallet.address,
        spender: bidderWallet.address,
        sellOnShare: Decimal.new(10),
      }

      await mintCurrency(defaultBid.currency, largerValidBid.bidder, largerValidBid.amount)
      await approveCurrency(defaultBid.currency, maket.address, bidderWallet)

      const beforeBalance = toNumWei(await getBalance(defaultBid.currency, defaultBid.bidder))

      await expect(setBid(maket, largerValidBid, defaultTokenId)).fulfilled

      const afterBalance = toNumWei(await getBalance(defaultBid.currency, largerValidBid.bidder))
      const bid = await maket.bidForTokenBidder(1, bidderWallet.address)
      expect(bid.currency).eq(defaultBid.currency)
      expect(toNumWei(bid.amount)).eq(largerValidBid.amount)
      expect(bid.bidder).eq(largerValidBid.bidder)
      expect(beforeBalance).eq(afterBalance + largerValidBid.amount)
    })

    it('should refund the original bid if the bidder bids again', async () => {
      const maket = await maketAs(mockTokenWallet)
      await setBidShares(maket, defaultTokenId, defaultBidShares)
      await mintCurrency(defaultBid.currency, defaultBid.bidder, 5000)
      await approveCurrency(defaultBid.currency, maket.address, bidderWallet)

      const bidderBalance = toNumWei(await ZOO__factory.connect(defaultBid.currency, bidderWallet).balanceOf(bidderWallet.address))

      await setBid(maket, defaultBid, defaultTokenId)
      await expect(setBid(maket, { ...defaultBid, amount: defaultBid.amount * 2 }, defaultTokenId)).fulfilled

      const afterBalance = toNumWei(await ZOO__factory.connect(defaultBid.currency, bidderWallet).balanceOf(bidderWallet.address))
      await expect(afterBalance).eq(bidderBalance - defaultBid.amount * 2)
    })

    it('should emit a bid event', async () => {
      const maket = await maketAs(mockTokenWallet)
      await setBidShares(maket, defaultTokenId, defaultBidShares)
      await mintCurrency(defaultBid.currency, defaultBid.bidder, 5000)
      await approveCurrency(defaultBid.currency, maket.address, bidderWallet)

      const block = await provider.getBlockNumber()
      await setBid(maket, defaultBid, defaultTokenId)
      const events = await maket.queryFilter(maket.filters.BidCreated(null, null), block)

      expect(events.length).eq(1)
      const logDescription = maket.interface.parseLog(events[0])
      expect(toNumWei(logDescription.args.tokenId)).to.eq(defaultTokenId)
      expect(toNumWei(logDescription.args.bid.amount)).to.eq(defaultBid.amount)
      expect(logDescription.args.bid.currency).to.eq(defaultBid.currency)
      expect(toNumWei(logDescription.args.bid.sellOnShare.value)).to.eq(toNumWei(defaultBid.sellOnShare.value))
    })
  })
})
