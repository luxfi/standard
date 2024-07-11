import chai, { expect } from 'chai'
import asPromised from 'chai-as-promised'
import { JsonRpcProvider } from '@ethersproject/providers'
import { Blockchain } from '../utils/Blockchain'
import { generatedWallets } from '../utils/generatedWallets'
import { ethers, Wallet } from 'ethers'
import { LogDescription } from '@ethersproject/abi'
import { AddressZero } from '@ethersproject/constants'
import Decimal from '../utils/Decimal'
import { BigNumber, BigNumberish, Bytes } from 'ethers'
import { ZOO__factory, Market__factory, Media__factory, ZooKeeper__factory, Market } from '../types'
import { Media } from '../types/Media'
import { approveCurrency, deployCurrency, EIP712Sig, getBalance, mintCurrency, signMintWithSig, signPermit, toNumWei } from './utils'
import { arrayify, formatBytes32String, formatUnits, sha256 } from 'ethers/lib/utils'
import exp from 'constants'

chai.use(asPromised)

let provider = new JsonRpcProvider()
let blockchain = new Blockchain(provider)

let market: Market

let contentHex: string
let contentHash: string
let contentHashBytes: Bytes
let otherContentHex: string
let otherContentHash: string
let otherContentHashBytes: Bytes
let zeroContentHashBytes: Bytes
let metadataHex: string
let metadataHash: string
let metadataHashBytes: Bytes

let tokenURI = 'www.example.com'
let metadataURI = 'www.example2.com'

type DecimalValue = { value: BigNumber }

type BidShares = {
  owner: DecimalValue
  prevOwner: DecimalValue
  creator: DecimalValue
}

type MediaData = {
  tokenURI: string
  metadataURI: string
  contentHash: Bytes
  metadataHash: Bytes
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

describe('Media', () => {
  let [deployerWallet, bidderWallet, creatorWallet, ownerWallet, prevOwnerWallet, otherWallet, nonBidderWallet] = generatedWallets(provider)

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
  const defaultBid = (currency: string, bidder: string, recipient?: string) => ({
    amount: 100,
    currency,
    bidder,
    recipient: recipient || bidder,
    sellOnShare: Decimal.new(10),
  })

  let mediaAddress: string
  let marketAddress: string
  let tokenAddress: string
  let keeperAddress: string

  async function mediaAs(wallet: Wallet) {
    return Media__factory.connect(mediaAddress, wallet)
  }

  async function deploy() {
    const token = await (await new ZOO__factory(deployerWallet).deploy()).deployed()
    tokenAddress = token.address

    const market = await (await new Market__factory(deployerWallet).deploy()).deployed()
    marketAddress = market.address

    const media = await (await new Media__factory(deployerWallet).deploy('ANML', 'CryptoZoo')).deployed()
    mediaAddress = media.address

    const keeper = await (await new ZooKeeper__factory(deployerWallet).deploy()).deployed()
    keeperAddress = keeper.address

    await market.configure(mediaAddress)
  }

  async function mint(media: Media, metadataURI: string, tokenURI: string, contentHash: Bytes, metadataHash: Bytes, shares: BidShares) {
    const data: MediaData = {
      tokenURI,
      metadataURI,
      contentHash,
      metadataHash,
    }
    return media.mint(data, shares)
  }

  async function mintWithSig(media: Media, creator: string, tokenURI: string, metadataURI: string, contentHash: Bytes, metadataHash: Bytes, shares: BidShares, sig: EIP712Sig) {
    const data: MediaData = {
      tokenURI,
      metadataURI,
      contentHash,
      metadataHash,
    }

    return media.mintWithSig(creator, data, shares, sig)
  }

  async function setAsk(media: Media, mediaId: number, ask: Ask) {
    return media.setAsk(mediaId, ask)
  }

  async function removeAsk(media: Media, mediaId: number) {
    return media.removeAsk(mediaId)
  }

  async function setBid(media: Media, bid: Bid, mediaId: number) {
    return media.setBid(mediaId, bid)
  }

  async function removeBid(media: Media, mediaId: number) {
    return media.removeBid(mediaId)
  }

  async function acceptBid(media: Media, mediaId: number, bid: Bid) {
    return media.acceptBid(mediaId, bid)
  }

  // Trade a media a few times and create some open bids
  async function setupAuction(currencyAddr: string, mediaId = 0) {
    const asCreator = await mediaAs(creatorWallet)
    const asPrevOwner = await mediaAs(prevOwnerWallet)
    const asOwner = await mediaAs(ownerWallet)
    const asBidder = await mediaAs(bidderWallet)
    const asOther = await mediaAs(otherWallet)

    await mintCurrency(currencyAddr, creatorWallet.address, 10000)
    await mintCurrency(currencyAddr, prevOwnerWallet.address, 10000)
    await mintCurrency(currencyAddr, ownerWallet.address, 10000)
    await mintCurrency(currencyAddr, bidderWallet.address, 10000)
    await mintCurrency(currencyAddr, otherWallet.address, 10000)
    await approveCurrency(currencyAddr, marketAddress, creatorWallet)
    await approveCurrency(currencyAddr, marketAddress, prevOwnerWallet)
    await approveCurrency(currencyAddr, marketAddress, ownerWallet)
    await approveCurrency(currencyAddr, marketAddress, bidderWallet)
    await approveCurrency(currencyAddr, marketAddress, otherWallet)

    await mint(asCreator, metadataURI, tokenURI, contentHashBytes, metadataHashBytes, defaultBidShares)

    await setBid(asPrevOwner, defaultBid(currencyAddr, prevOwnerWallet.address), mediaId)
    await acceptBid(asCreator, mediaId, {
      ...defaultBid(currencyAddr, prevOwnerWallet.address),
    })
    await setBid(asOwner, defaultBid(currencyAddr, ownerWallet.address), mediaId)
    await acceptBid(asPrevOwner, mediaId, defaultBid(currencyAddr, ownerWallet.address))
    await setBid(asBidder, defaultBid(currencyAddr, bidderWallet.address), mediaId)
    await setBid(asOther, defaultBid(currencyAddr, otherWallet.address), mediaId)
  }

  beforeEach(async () => {
    await deploy()
    await blockchain.resetAsync()

    metadataHex = ethers.utils.formatBytes32String('{}')
    metadataHash = await sha256(metadataHex)
    metadataHashBytes = ethers.utils.arrayify(metadataHash)

    contentHex = ethers.utils.formatBytes32String('invert')
    contentHash = await sha256(contentHex)
    contentHashBytes = ethers.utils.arrayify(contentHash)

    otherContentHex = ethers.utils.formatBytes32String('otherthing')
    otherContentHash = await sha256(otherContentHex)
    otherContentHashBytes = ethers.utils.arrayify(otherContentHash)

    zeroContentHashBytes = ethers.utils.arrayify(ethers.constants.HashZero)
  })

  describe('#constructor', () => {
    it('should be able to deploy', async () => {
      await expect(deploy()).eventually.fulfilled
    })
  })

  describe('#mint', () => {
    beforeEach(async () => {
      await deploy()
    })

    it('should mint a media', async () => {
      const media = await mediaAs(creatorWallet)

      await expect(
        mint(media, metadataURI, tokenURI, contentHashBytes, metadataHashBytes, {
          prevOwner: Decimal.new(10),
          creator: Decimal.new(90),
          owner: Decimal.new(0),
        }),
      ).fulfilled

      const t = await media.tokenByIndex(0)
      const ownerT = await media.tokenOfOwnerByIndex(creatorWallet.address, 0)
      const ownerOf = await media.ownerOf(0)
      const creator = await media.tokenCreators(0)
      const prevOwner = await media.previousTokenOwners(0)
      const tokenContentHash = await media.tokenContentHashes(0)
      const metadataContentHash = await media.tokenMetadataHashes(0)
      const savedtokenURI = await media.tokenURI(0)
      const savedMetadataURI = await media.tokenMetadataURI(0)

      // expect(toNumWei(t)).eq(toNumWei(ownerT));
      expect(ownerOf).eq(creatorWallet.address)
      expect(creator).eq(creatorWallet.address)
      expect(prevOwner).eq(creatorWallet.address)
      expect(tokenContentHash).eq(contentHash)
      expect(metadataContentHash).eq(metadataHash)
      expect(savedtokenURI).eq(tokenURI)
      expect(savedMetadataURI).eq(metadataURI)
    })

    it('should revert if an empty content hash is specified', async () => {
      const media = await mediaAs(creatorWallet)

      await expect(
        mint(media, metadataURI, tokenURI, zeroContentHashBytes, metadataHashBytes, {
          prevOwner: Decimal.new(10),
          creator: Decimal.new(90),
          owner: Decimal.new(0),
        }),
      ).rejectedWith('Media: content hash must be non-zero')
    })

    it('should revert if the content hash already exists for a created media', async () => {
      const media = await mediaAs(creatorWallet)

      await expect(
        mint(media, metadataURI, tokenURI, contentHashBytes, metadataHashBytes, {
          prevOwner: Decimal.new(10),
          creator: Decimal.new(90),
          owner: Decimal.new(0),
        }),
      ).fulfilled

      let passed = true
      try {
        await mint(media, metadataURI, tokenURI, contentHashBytes, metadataHashBytes, {
          prevOwner: Decimal.new(10),
          creator: Decimal.new(90),
          owner: Decimal.new(0),
        })
        passed = false
      } catch (error) {
        expect(error.error.body).to.contain('Media: a token has already been created with this content hash', 'This error body should have the correct revert error')
      }
      passed = true
      expect(passed, 'The previous tx was not reverted').to.be.true
    })

    it('should revert if the metadataHash is empty', async () => {
      const media = await mediaAs(creatorWallet)

      await expect(
        mint(media, metadataURI, tokenURI, contentHashBytes, zeroContentHashBytes, {
          prevOwner: Decimal.new(10),
          creator: Decimal.new(90),
          owner: Decimal.new(0),
        }),
      ).rejectedWith('Media: metadata hash must be non-zero')
    })

    it('should revert if the tokenURI is empty', async () => {
      const media = await mediaAs(creatorWallet)

      await expect(
        mint(media, metadataURI, '', zeroContentHashBytes, metadataHashBytes, {
          prevOwner: Decimal.new(10),
          creator: Decimal.new(90),
          owner: Decimal.new(0),
        }),
      ).rejectedWith('Media: specified uri must be non-empty')
    })

    it('should revert if the metadataURI is empty', async () => {
      const media = await mediaAs(creatorWallet)

      await expect(
        mint(media, '', tokenURI, zeroContentHashBytes, metadataHashBytes, {
          prevOwner: Decimal.new(10),
          creator: Decimal.new(90),
          owner: Decimal.new(0),
        }),
      ).rejectedWith('Media: specified uri must be non-empty')
    })

    it('should not be able to mint a media with bid shares summing to less than 100', async () => {
      const media = await mediaAs(creatorWallet)

      await expect(
        mint(media, metadataURI, tokenURI, contentHashBytes, metadataHashBytes, {
          prevOwner: Decimal.new(15),
          owner: Decimal.new(15),
          creator: Decimal.new(15),
        }),
      ).rejectedWith('Market: Invalid bid shares, must sum to 100')
    })

    it('should not be able to mint a media with bid shares summing to greater than 100', async () => {
      const media = await mediaAs(creatorWallet)

      await expect(
        mint(media, metadataURI, '222', contentHashBytes, metadataHashBytes, {
          prevOwner: Decimal.new(99),
          owner: Decimal.new(1),
          creator: Decimal.new(1),
        }),
      ).rejectedWith('Market: Invalid bid shares, must sum to 100')
    })
  })

  describe('#mintWithSig', () => {
    beforeEach(async () => {
      await deploy()
    })

    it('should mint a media for a given creator with a valid signature', async () => {
      const media = await mediaAs(otherWallet)
      const market = await Market__factory.connect(marketAddress, otherWallet)
      const sig = await signMintWithSig(creatorWallet, media.address, creatorWallet.address, contentHash, metadataHash, Decimal.new(5).value.toString(), 1)

      const beforeNonce = await media.mintWithSigNonces(creatorWallet.address)
      await expect(
        mintWithSig(
          media,
          creatorWallet.address,
          tokenURI,
          metadataURI,
          contentHashBytes,
          metadataHashBytes,
          {
            prevOwner: Decimal.new(0),
            owner: Decimal.new(95),
            creator: Decimal.new(5),
          },
          sig,
        ),
      ).fulfilled

      const recovered = await media.tokenCreators(0)
      const recoveredtokenURI = await media.tokenURI(0)
      const recoveredMetadataURI = await media.tokenMetadataURI(0)
      const recoveredContentHash = await media.tokenContentHashes(0)
      const recoveredMetadataHash = await media.tokenMetadataHashes(0)
      const recoveredCreatorBidShare = formatUnits((await market.bidSharesForToken(0)).creator.value, 'ether')
      const afterNonce = await media.mintWithSigNonces(creatorWallet.address)

      expect(recovered).to.eq(creatorWallet.address)
      expect(recoveredtokenURI).to.eq(tokenURI)
      expect(recoveredMetadataURI).to.eq(metadataURI)
      expect(recoveredContentHash).to.eq(contentHash)
      expect(recoveredMetadataHash).to.eq(metadataHash)
      expect(recoveredCreatorBidShare).to.eq('5.0')
      expect(toNumWei(afterNonce)).to.eq(toNumWei(beforeNonce) + 1)
    })

    it('should not mint a media for a different creator', async () => {
      const media = await mediaAs(otherWallet)
      const sig = await signMintWithSig(bidderWallet, media.address, creatorWallet.address, tokenURI, metadataURI, Decimal.new(5).value.toString(), 1)

      await expect(
        mintWithSig(
          media,
          creatorWallet.address,
          tokenURI,
          metadataURI,
          contentHashBytes,
          metadataHashBytes,
          {
            prevOwner: Decimal.new(0),
            owner: Decimal.new(95),
            creator: Decimal.new(5),
          },
          sig,
        ),
      ).rejectedWith('Media: Signature invalid')
    })

    it('should not mint a media for a different contentHash', async () => {
      const badContent = 'bad bad bad'
      const badContentHex = formatBytes32String(badContent)
      const badContentHash = sha256(badContentHex)
      const badContentHashBytes = arrayify(badContentHash)

      const media = await mediaAs(otherWallet)
      const sig = await signMintWithSig(creatorWallet, media.address, creatorWallet.address, contentHash, metadataHash, Decimal.new(5).value.toString(), 1)

      await expect(
        mintWithSig(
          media,
          creatorWallet.address,
          tokenURI,
          metadataURI,
          badContentHashBytes,
          metadataHashBytes,
          {
            prevOwner: Decimal.new(0),
            owner: Decimal.new(95),
            creator: Decimal.new(5),
          },
          sig,
        ),
      ).rejectedWith('Media: Signature invalid')
    })
    it('should not mint a media for a different metadataHash', async () => {
      const badMetadata = '{"some": "bad", "data": ":)"}'
      const badMetadataHex = formatBytes32String(badMetadata)
      const badMetadataHash = sha256(badMetadataHex)
      const badMetadataHashBytes = arrayify(badMetadataHash)
      const media = await mediaAs(otherWallet)
      const sig = await signMintWithSig(creatorWallet, media.address, creatorWallet.address, contentHash, metadataHash, Decimal.new(5).value.toString(), 1)

      await expect(
        mintWithSig(
          media,
          creatorWallet.address,
          tokenURI,
          metadataURI,
          contentHashBytes,
          badMetadataHashBytes,
          {
            prevOwner: Decimal.new(0),
            owner: Decimal.new(95),
            creator: Decimal.new(5),
          },
          sig,
        ),
      ).rejectedWith('Media: Signature invalid')
    })
    it('should not mint a media for a different creator bid share', async () => {
      const media = await mediaAs(otherWallet)
      const sig = await signMintWithSig(creatorWallet, media.address, creatorWallet.address, tokenURI, metadataURI, Decimal.new(5).value.toString(), 1)

      await expect(
        mintWithSig(
          media,
          creatorWallet.address,
          tokenURI,
          metadataURI,
          contentHashBytes,
          metadataHashBytes,
          {
            prevOwner: Decimal.new(0),
            owner: Decimal.new(100),
            creator: Decimal.new(0),
          },
          sig,
        ),
      ).rejectedWith('Media: Signature invalid')
    })
    it('should not mint a media with an invalid deadline', async () => {
      const media = await mediaAs(otherWallet)
      const sig = await signMintWithSig(creatorWallet, media.address, creatorWallet.address, tokenURI, metadataURI, Decimal.new(5).value.toString(), 1)

      await expect(
        mintWithSig(
          media,
          creatorWallet.address,
          tokenURI,
          metadataURI,
          contentHashBytes,
          metadataHashBytes,
          {
            prevOwner: Decimal.new(0),
            owner: Decimal.new(95),
            creator: Decimal.new(5),
          },
          { ...sig, deadline: '1' },
        ),
      ).rejectedWith('Media: mintWithSig expired')
    })
  })

  describe('#setAsk', () => {
    let currencyAddr: string
    beforeEach(async () => {
      await deploy()
      currencyAddr = await deployCurrency()
      await setupAuction(currencyAddr)
    })

    it('should set the ask', async () => {
      const media = await mediaAs(ownerWallet)
      await expect(setAsk(media, 0, defaultAsk)).fulfilled
    })

    it('should reject if the ask is 0', async () => {
      const media = await mediaAs(ownerWallet)
      await expect(setAsk(media, 0, { ...defaultAsk, amount: 0 })).rejectedWith('Market: Ask invalid for share splitting')
    })

    it('should reject if the ask amount is invalid and cannot be split', async () => {
      const media = await mediaAs(ownerWallet)
      await expect(setAsk(media, 0, { ...defaultAsk, amount: 101 })).rejectedWith('Market: Ask invalid for share splitting')
    })
  })

  describe('#removeAsk', () => {
    let media: Media
    beforeEach(async () => {
      media = await (await mediaAs(creatorWallet)).deployed()
      await mint(media, metadataURI, tokenURI, contentHashBytes, metadataHashBytes, {
        prevOwner: Decimal.new(10),
        creator: Decimal.new(90),
        owner: Decimal.new(0),
      })
    })
    it('should remove the ask', async () => {
      const market = await Market__factory.connect(marketAddress, deployerWallet).deployed()
      await setAsk(media, 0, defaultAsk)

      await expect(removeAsk(media, 0)).fulfilled
      const ask = await market.currentAskForToken(0)
      expect(toNumWei(ask.amount)).eq(0)
      expect(ask.currency).eq(AddressZero)
    })

    it('should emit an Ask Removed event', async () => {
      const auction = await Market__factory.connect(marketAddress, deployerWallet).deployed()
      await setAsk(media, 0, defaultAsk)
      const block = await provider.getBlockNumber()
      const tx = await removeAsk(media, 0)

      const events = await auction.queryFilter(auction.filters.AskRemoved(0, null), block)
      expect(events.length).eq(1)
      let logDescription: LogDescription
      logDescription = auction.interface.parseLog(events[0])
      expect(toNumWei(logDescription.args.tokenId)).to.eq(0)
      expect(toNumWei(logDescription.args.ask.amount)).to.eq(defaultAsk.amount)
      expect(logDescription.args.ask.currency).to.eq(defaultAsk.currency)
    })

    it('should not be callable by anyone that is not owner or approved', async () => {
      await setAsk(media, 0, defaultAsk)
      let passed = true
      try {
        await media.connect(otherWallet).removeAsk(0)
      } catch (error) {
        expect(error.error.body).to.contain('Media: Only approved or owner')
        passed = false
      }
      expect(passed, 'Previous tx should have reverted').to.be.false
    })
  })

  describe('#setBid', () => {
    let currencyAddr: string
    beforeEach(async () => {
      await deploy()
      await mint(await mediaAs(creatorWallet), metadataURI, '1111', otherContentHashBytes, metadataHashBytes, defaultBidShares)
      currencyAddr = await deployCurrency()
    })

    it('should revert if the media bidder does not have a high enough allowance for their bidding currency', async () => {
      const media = await mediaAs(bidderWallet)
      let passed = false
      try {
        media.setBid(0, defaultBid(currencyAddr, bidderWallet.address))
        passed = true
      } catch (error) {
        expect(error).to.contain('SafeERC20: ERC20 operation did not succeed')
        passed = true
      }
      expect(passed, 'The previous transaction was not reverted').to.be.true
    })

    it('should revert if the media bidder does not have a high enough balance for their bidding currency', async () => {
      const media = await mediaAs(bidderWallet)
      await approveCurrency(currencyAddr, marketAddress, bidderWallet)
      let passed = false
      try {
        media.setBid(0, defaultBid(currencyAddr, bidderWallet.address))
        passed = true
      } catch (error) {
        expect(error).to.contain('SafeERC20: ERC20 operation did not succeed')
        passed = true
      }
      expect(passed, 'The previous transaction was not reverted').to.be.true
    })

    it('should set a bid', async () => {
      const media = await mediaAs(bidderWallet)
      await approveCurrency(currencyAddr, marketAddress, bidderWallet)
      await mintCurrency(currencyAddr, bidderWallet.address, 100000)
      await expect(media.setBid(0, defaultBid(currencyAddr, bidderWallet.address))).fulfilled
      const balance = await getBalance(currencyAddr, bidderWallet.address)
      expect(toNumWei(balance)).eq(100000 - 100)
    })

    it('should automatically transfer the media if the ask is set', async () => {
      const media = await mediaAs(bidderWallet)
      const asOwner = await mediaAs(ownerWallet)
      await setupAuction(currencyAddr, 1)
      await setAsk(asOwner, 1, { ...defaultAsk, currency: currencyAddr })

      await expect(media.setBid(1, defaultBid(currencyAddr, bidderWallet.address))).fulfilled

      await expect(media.ownerOf(1)).eventually.eq(bidderWallet.address)
    })

    it('should refund a bid if one already exists for the bidder', async () => {
      const media = await mediaAs(bidderWallet)
      await setupAuction(currencyAddr, 1)

      const beforeBalance = toNumWei(await getBalance(currencyAddr, bidderWallet.address))
      await setBid(
        media,
        {
          currency: currencyAddr,
          amount: 200,
          bidder: bidderWallet.address,
          recipient: otherWallet.address,
          sellOnShare: Decimal.new(10),
        },
        1,
      )
      const afterBalance = toNumWei(await getBalance(currencyAddr, bidderWallet.address))

      expect(afterBalance).eq(beforeBalance - 100)
    })
  })

  describe('#removeBid', () => {
    let currencyAddr: string
    beforeEach(async () => {
      await deploy()
      currencyAddr = await deployCurrency()
      await setupAuction(currencyAddr)
    })

    it('should revert if the bidder has not placed a bid', async () => {
      const media = await mediaAs(nonBidderWallet)

      await expect(removeBid(media, 0)).rejectedWith('Market: cannot remove bid amount of 0')
    })

    it('should revert if the mediaId has not yet ben created', async () => {
      const media = await mediaAs(bidderWallet)
      let passed = false
      try {
        await removeBid(media, 100)
        passed = true
      } catch (error) {
        expect(error.error.body).to.contain('Media: token with that id does not exist')
        passed = true
      }
      expect(passed, 'The previous transaction was not reverted').to.be.true
    })

    it('should remove a bid and refund the bidder', async () => {
      const media = await mediaAs(bidderWallet)
      const beforeBalance = toNumWei(await getBalance(currencyAddr, bidderWallet.address))
      await expect(removeBid(media, 0)).fulfilled
      const afterBalance = toNumWei(await getBalance(currencyAddr, bidderWallet.address))

      expect(afterBalance).eq(beforeBalance + 100)
    })

    it('should not be able to remove a bid twice', async () => {
      const media = await mediaAs(bidderWallet)
      await removeBid(media, 0)

      await expect(removeBid(media, 0)).rejectedWith('Market: cannot remove bid amount of 0')
    })

    it('should remove a bid, even if the media is burned', async () => {
      const asOwner = await mediaAs(ownerWallet)
      const asBidder = await mediaAs(bidderWallet)
      const asCreator = await mediaAs(creatorWallet)

      await asOwner.transferFrom(ownerWallet.address, creatorWallet.address, 0)
      await asCreator.burn(0)
      const beforeBalance = toNumWei(await getBalance(currencyAddr, bidderWallet.address))
      await expect(asBidder.removeBid(0)).fulfilled
      const afterBalance = toNumWei(await getBalance(currencyAddr, bidderWallet.address))
      expect(afterBalance).eq(beforeBalance + 100)
    })
  })

  describe('#acceptBid', () => {
    let currencyAddr: string
    beforeEach(async () => {
      await deploy()
      currencyAddr = await deployCurrency()
      await setupAuction(currencyAddr)
    })

    it('should accept a bid', async () => {
      const media = await mediaAs(ownerWallet)
      const auction = await Market__factory.connect(marketAddress, bidderWallet)
      const asBidder = await mediaAs(bidderWallet)
      const bid = {
        ...defaultBid(currencyAddr, bidderWallet.address, otherWallet.address),
        sellOnShare: Decimal.new(15),
      }
      await setBid(asBidder, bid, 0)

      const beforeOwnerBalance = toNumWei(await getBalance(currencyAddr, ownerWallet.address))
      const beforePrevOwnerBalance = toNumWei(await getBalance(currencyAddr, prevOwnerWallet.address))
      const beforeCreatorBalance = toNumWei(await getBalance(currencyAddr, creatorWallet.address))
      await expect(media.acceptBid(0, bid)).fulfilled
      const newOwner = await media.ownerOf(0)
      const afterOwnerBalance = toNumWei(await getBalance(currencyAddr, ownerWallet.address))
      const afterPrevOwnerBalance = toNumWei(await getBalance(currencyAddr, prevOwnerWallet.address))
      const afterCreatorBalance = toNumWei(await getBalance(currencyAddr, creatorWallet.address))
      const bidShares = await market.bidSharesForToken(0)

      expect(afterOwnerBalance).eq(beforeOwnerBalance + 80)
      expect(afterPrevOwnerBalance).eq(beforePrevOwnerBalance + 10)
      expect(afterCreatorBalance).eq(beforeCreatorBalance + 10)
      expect(newOwner).eq(otherWallet.address)
      expect(toNumWei(bidShares[2].value)).eq(75 * 10 ** 18)
      expect(toNumWei(bidShares[0].value)).eq(15 * 10 ** 18)
      expect(toNumWei(bidShares[1].value)).eq(10 * 10 ** 18)
    })

    it('should emit a bid finalized event if the bid is accepted', async () => {
      const asBidder = await mediaAs(bidderWallet)
      const media = await mediaAs(ownerWallet)
      const auction = await Market__factory.connect(marketAddress, bidderWallet)
      const bid = defaultBid(currencyAddr, bidderWallet.address)
      const block = await provider.getBlockNumber()
      await setBid(asBidder, bid, 0)
      await media.acceptBid(0, bid)
      const events = await auction.queryFilter(auction.filters.BidFinalized(null, null), block)
      expect(events.length).eq(1)
      const logDescription: LogDescription = auction.interface.parseLog(events[0])
      expect(toNumWei(logDescription.args.tokenId)).to.eq(0)
      expect(toNumWei(logDescription.args.bid.amount)).to.eq(bid.amount)
      expect(logDescription.args.bid.currency).to.eq(bid.currency)
      expect(toNumWei(logDescription.args.bid.sellOnShare.value)).to.eq(toNumWei(bid.sellOnShare.value))
      expect(logDescription.args.bid.bidder).to.eq(bid.bidder)
    })

    it('should emit a bid shares updated event if the bid is accepted', async () => {
      const asBidder = await mediaAs(bidderWallet)
      const media = await mediaAs(ownerWallet)
      const auction = await Market__factory.connect(marketAddress, bidderWallet)
      const bid = defaultBid(currencyAddr, bidderWallet.address)
      const block = await provider.getBlockNumber()
      await setBid(asBidder, bid, 0)
      await media.acceptBid(0, bid)
      const events = await auction.queryFilter(auction.filters.BidShareUpdated(null, null), block)
      expect(events.length).eq(1)
      const logDescription: LogDescription = auction.interface.parseLog(events[0])
      expect(toNumWei(logDescription.args.tokenId)).to.eq(0)
      expect(toNumWei(logDescription.args.bidShares.prevOwner.value)).to.eq(10000000000000000000)
      expect(toNumWei(logDescription.args.bidShares.owner.value)).to.eq(80000000000000000000)
      expect(toNumWei(logDescription.args.bidShares.creator.value)).to.eq(10000000000000000000)
    })

    it('should revert if not called by the owner', async () => {
      const media = await mediaAs(otherWallet)

      await expect(media.acceptBid(0, { ...defaultBid(currencyAddr, otherWallet.address) })).rejectedWith('Media: Only approved or owner')
    })

    it('should revert if a non-existent bid is accepted', async () => {
      const media = await mediaAs(ownerWallet)
      await expect(media.acceptBid(0, { ...defaultBid(currencyAddr, AddressZero) })).rejectedWith('Market: cannot accept bid of 0')
    })

    it('should revert if an invalid bid is accepted', async () => {
      const media = await mediaAs(ownerWallet)
      const asBidder = await mediaAs(bidderWallet)
      const bid = {
        ...defaultBid(currencyAddr, bidderWallet.address),
        amount: 99,
      }
      await setBid(asBidder, bid, 0)

      await expect(media.acceptBid(0, bid)).rejectedWith('Market: Bid invalid for share splitting')
    })

    // TODO: test the front running logic
  })

  describe('#transfer', () => {
    let currencyAddr: string
    beforeEach(async () => {
      await deploy()
      currencyAddr = await deployCurrency()
      await setupAuction(currencyAddr)
    })

    it('should remove the ask after a transfer', async () => {
      const media = await mediaAs(ownerWallet)
      const auction = Market__factory.connect(marketAddress, deployerWallet)
      await setAsk(media, 0, defaultAsk)

      await expect(media.transferFrom(ownerWallet.address, otherWallet.address, 0)).fulfilled
      const ask = await auction.currentAskForToken(0)
      await expect(toNumWei(ask.amount)).eq(0)
      await expect(ask.currency).eq(AddressZero)
    })
  })

  describe('#burn', () => {
    beforeEach(async () => {
      await deploy()
      const media = await mediaAs(creatorWallet)
      await mint(media, metadataURI, tokenURI, contentHashBytes, metadataHashBytes, {
        prevOwner: Decimal.new(10),
        creator: Decimal.new(90),
        owner: Decimal.new(0),
      })
    })

    it('should revert when the caller is the owner, but not creator', async () => {
      const creatormedia = await mediaAs(creatorWallet)
      await creatormedia.transferFrom(creatorWallet.address, ownerWallet.address, 0)
      const media = await mediaAs(ownerWallet)
      await expect(media.burn(0)).rejectedWith('Media: owner is not creator of media')
    })

    it('should revert when the caller is approved, but the owner is not the creator', async () => {
      const creatormedia = await mediaAs(creatorWallet)
      await creatormedia.transferFrom(creatorWallet.address, ownerWallet.address, 0)
      const media = await mediaAs(ownerWallet)
      await media.approve(otherWallet.address, 0)

      const otherToken = await mediaAs(otherWallet)
      await expect(otherToken.burn(0)).rejectedWith('Media: owner is not creator of media')
    })

    it('should revert when the caller is not the owner or a creator', async () => {
      const media = await mediaAs(otherWallet)

      await expect(media.burn(0)).rejectedWith('Media: Only approved or owner')
    })

    it('should revert if the media id does not exist', async () => {
      const media = await mediaAs(creatorWallet)

      await expect(media.burn(100)).rejectedWith('Media: nonexistent media')
    })

    it('should clear approvals, set remove owner, but maintain tokenURI and contentHash when the owner is creator and caller', async () => {
      const media = await mediaAs(creatorWallet)
      await expect(media.approve(otherWallet.address, 0)).fulfilled

      await expect(media.burn(0)).fulfilled

      await expect(media.ownerOf(0)).rejectedWith('ERC721: owner query for nonexistent media')

      const totalSupply = await media.totalSupply()
      expect(toNumWei(totalSupply)).eq(0)

      await expect(media.getApproved(0)).rejectedWith('ERC721: approved query for nonexistent media')

      const tokenURI = await media.tokenURI(0)
      expect(tokenURI).eq('www.example.com')

      const contentHash = await media.tokenContentHashes(0)
      expect(contentHash).eq(contentHash)

      const previousOwner = await media.previousTokenOwners(0)
      expect(previousOwner).eq(AddressZero)
    })

    it('should clear approvals, set remove owner, but maintain tokenURI and contentHash when the owner is creator and caller is approved', async () => {
      const media = await mediaAs(creatorWallet)
      await expect(media.approve(otherWallet.address, 0)).fulfilled

      const otherToken = await mediaAs(otherWallet)

      await expect(otherToken.burn(0)).fulfilled

      await expect(media.ownerOf(0)).rejectedWith('ERC721: owner query for nonexistent media')

      const totalSupply = await media.totalSupply()
      expect(toNumWei(totalSupply)).eq(0)

      await expect(media.getApproved(0)).rejectedWith('ERC721: approved query for nonexistent media')

      const tokenURI = await media.tokenURI(0)
      expect(tokenURI).eq('www.example.com')

      const contentHash = await media.tokenContentHashes(0)
      expect(contentHash).eq(contentHash)

      const previousOwner = await media.previousTokenOwners(0)
      expect(previousOwner).eq(AddressZero)
    })
  })

  describe('#updateTokenURI', async () => {
    let currencyAddr: string

    beforeEach(async () => {
      await deploy()
      currencyAddr = await deployCurrency()
      await setupAuction(currencyAddr)
    })

    it('should revert if the media does not exist', async () => {
      const media = await mediaAs(creatorWallet)

      await expect(media.updateTokenURI(1, 'blah blah')).rejectedWith('ERC721: operator query for nonexistent media')
    })

    it('should revert if the caller is not the owner of the media and does not have approval', async () => {
      const media = await mediaAs(otherWallet)

      await expect(media.updateTokenURI(0, 'blah blah')).rejectedWith('Media: Only approved or owner')
    })

    it('should revert if the uri is empty string', async () => {
      const media = await mediaAs(ownerWallet)
      await expect(media.updateTokenURI(0, '')).rejectedWith('Media: specified uri must be non-empty')
    })

    it('should revert if the media has been burned', async () => {
      const media = await mediaAs(creatorWallet)

      await mint(media, metadataURI, tokenURI, otherContentHashBytes, metadataHashBytes, {
        prevOwner: Decimal.new(10),
        creator: Decimal.new(90),
        owner: Decimal.new(0),
      })

      await expect(media.burn(1)).fulfilled

      await expect(media.updateTokenURI(1, 'blah')).rejectedWith('ERC721: operator query for nonexistent media')
    })

    it('should set the tokenURI to the URI passed if the msg.sender is the owner', async () => {
      const media = await mediaAs(ownerWallet)
      await expect(media.updateTokenURI(0, 'blah blah')).fulfilled

      const tokenURI = await media.tokenURI(0)
      expect(tokenURI).eq('blah blah')
    })

    it('should set the tokenURI to the URI passed if the msg.sender is approved', async () => {
      const media = await mediaAs(ownerWallet)
      await media.approve(otherWallet.address, 0)

      const otherToken = await mediaAs(otherWallet)
      await expect(otherToken.updateTokenURI(0, 'blah blah')).fulfilled

      const tokenURI = await media.tokenURI(0)
      expect(tokenURI).eq('blah blah')
    })
  })

  describe('#updateTokenMetadataURI', async () => {
    let currencyAddr: string

    beforeEach(async () => {
      await deploy()
      currencyAddr = await deployCurrency()
      await setupAuction(currencyAddr)
    })

    it('should revert if the media does not exist', async () => {
      const media = await mediaAs(creatorWallet)

      await expect(media.updateTokenMetadataURI(1, 'blah blah')).rejectedWith('ERC721: operator query for nonexistent media')
    })

    it('should revert if the caller is not the owner of the media or approved', async () => {
      const media = await mediaAs(otherWallet)

      await expect(media.updateTokenMetadataURI(0, 'blah blah')).rejectedWith('Media: Only approved or owner')
    })

    it('should revert if the uri is empty string', async () => {
      const media = await mediaAs(ownerWallet)
      await expect(media.updateTokenMetadataURI(0, '')).rejectedWith('Media: specified uri must be non-empty')
    })

    it('should revert if the media has been burned', async () => {
      const media = await mediaAs(creatorWallet)

      await mint(media, metadataURI, tokenURI, otherContentHashBytes, metadataHashBytes, {
        prevOwner: Decimal.new(10),
        creator: Decimal.new(90),
        owner: Decimal.new(0),
      })

      await expect(media.burn(1)).fulfilled

      await expect(media.updateTokenMetadataURI(1, 'blah')).rejectedWith('ERC721: operator query for nonexistent media')
    })

    it('should set the tokenMetadataURI to the URI passed if msg.sender is the owner', async () => {
      const media = await mediaAs(ownerWallet)
      await expect(media.updateTokenMetadataURI(0, 'blah blah')).fulfilled

      const tokenURI = await media.tokenMetadataURI(0)
      expect(tokenURI).eq('blah blah')
    })

    it('should set the tokenMetadataURI to the URI passed if the msg.sender is approved', async () => {
      const media = await mediaAs(ownerWallet)
      await media.approve(otherWallet.address, 0)

      const otherToken = await mediaAs(otherWallet)
      await expect(otherToken.updateTokenMetadataURI(0, 'blah blah')).fulfilled

      const tokenURI = await media.tokenMetadataURI(0)
      expect(tokenURI).eq('blah blah')
    })
  })

  describe('#permit', () => {
    let currency: string

    beforeEach(async () => {
      await deploy()
      currency = await deployCurrency()
      await setupAuction(currency)
    })

    it('should allow a wallet to set themselves to approved with a valid signature', async () => {
      const media = await mediaAs(otherWallet)
      const sig = await signPermit(
        ownerWallet,
        otherWallet.address,
        media.address,
        0,
        // NOTE: We set the chain ID to 1 because of an error with ganache-core: https://github.com/trufflesuite/ganache-core/issues/515
        1,
      )
      await expect(media.permit(otherWallet.address, 0, sig)).fulfilled
      await expect(media.getApproved(0)).eventually.eq(otherWallet.address)
    })

    it('should not allow a wallet to set themselves to approved with an invalid signature', async () => {
      const media = await mediaAs(otherWallet)
      const sig = await signPermit(ownerWallet, bidderWallet.address, media.address, 0, 1)
      await expect(media.permit(otherWallet.address, 0, sig)).rejectedWith('Media: Signature invalid')
      await expect(media.getApproved(0)).eventually.eq(AddressZero)
    })
  })

  describe('#supportsInterface', async () => {
    beforeEach(async () => {
      await deploy()
    })

    it('should return true to supporting new metadata interface', async () => {
      const media = await mediaAs(otherWallet)
      const interfaceId = ethers.utils.arrayify('0x4e222e66')
      const supportsId = await media.supportsInterface(interfaceId)
      expect(supportsId).eq(true)
    })

    it('should return false to supporting the old metadata interface', async () => {
      const media = await mediaAs(otherWallet)
      const interfaceId = ethers.utils.arrayify('0x5b5e139f')
      const supportsId = await media.supportsInterface(interfaceId)
      expect(supportsId).eq(false)
    })
  })

  describe('#revokeApproval', async () => {
    let currency: string

    beforeEach(async () => {
      await deploy()
      currency = await deployCurrency()
      await setupAuction(currency)
    })

    it('should revert if the caller is the owner', async () => {
      const media = await mediaAs(ownerWallet)
      await expect(media.revokeApproval(0)).rejectedWith('Media: caller not approved address')
    })

    it('should revert if the caller is the creator', async () => {
      const media = await mediaAs(creatorWallet)
      await expect(media.revokeApproval(0)).rejectedWith('Media: caller not approved address')
    })

    it('should revert if the caller is neither owner, creator, or approver', async () => {
      const media = await mediaAs(otherWallet)
      await expect(media.revokeApproval(0)).rejectedWith('Media: caller not approved address')
    })

    it('should revoke the approval for media id if caller is approved address', async () => {
      const media = await mediaAs(ownerWallet)
      await media.approve(otherWallet.address, 0)
      const otherToken = await mediaAs(otherWallet)
      await expect(otherToken.revokeApproval(0)).fulfilled
      const approved = await media.getApproved(0)
      expect(approved).eq(ethers.constants.AddressZero)
    })
  })
})
