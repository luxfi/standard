// @ts-ignore
import { ethers, deployments } from 'hardhat'
import { Auction, Market, Media, Market__factory, Media__factory, ZOO__factory, ZooKeeper__factory, BadBidder, BadERC721, TestERC721, ZOO  } from '../types'
import { sha256 } from 'ethers/lib/utils'
import Decimal from '../utils/Decimal'
import { BigNumber, BigNumberish, Contract } from 'ethers'
import { MaxUint256, AddressZero } from '@ethersproject/constants'
import { generatedWallets } from '../utils/generatedWallets'
import { JsonRpcProvider } from '@ethersproject/providers'
import { formatUnits } from '@ethersproject/units'
import { Wallet } from '@ethersproject/wallet'
import { recoverTypedMessage, recoverTypedSignature, signTypedData } from 'eth-sig-util'
import { bufferToHex, ecrecover, fromRpcSig, pubToAddress } from 'ethereumjs-util'
import { toUtf8Bytes } from 'ethers/lib/utils'
import { keccak256 } from '@ethersproject/keccak256'

let provider = new JsonRpcProvider()
let [deployerWallet] = generatedWallets(provider)

export const requireDependencies = () => {
  const chai = require('chai')
  const expect = chai.expect
  const asPromised = require('chai-as-promised')
  const { solidity } = require('ethereum-waffle')

  chai.use(asPromised)
  chai.use(solidity)

  return {
    chai,
    expect,
    asPromised,
    solidity,
  }
}

const deployContractsAsync = async (contractArr: string[]) => {
  return await contractArr.reduce(async (prev: Promise<{}>, name: string) => {
    const sum = await prev
    const contract: Contract = await ethers.getContract(name)
    sum[name] = contract;
    return sum;
  }, Promise.resolve({}))
}

export const setupTestFactory = (contractArr: string[]) =>
  deployments.createFixture(async ({ deployments, getNamedAccounts, ethers }, options) => {
    requireDependencies()
    await deployments.fixture(contractArr)

    let tokens: { [key: string]: Contract } = await deployContractsAsync(contractArr);
    // contractArr.reduce(async (sum: {}, name: string) => {
    //   const contract: Contract = await ethers.getContract(name)
    //   return {
    //     [name]: contract,
    //     ...sum,
    //   }
    // }, {})
    const signers = await ethers.getSigners()
    const owner = (await getNamedAccounts()).deployer
    return {
      deployments: deployments,
      owner: owner,
      signers: signers,
      tokens,
    }
  })

export async function deployCurrency() {
  const currency = await new ZOO__factory(deployerWallet).deploy()
  return currency.address
}

export async function mintCurrency(currency: string, to: string, value: number) {
  await ZOO__factory.connect(currency, deployerWallet).mint(to, value)
}

export async function approveCurrency(currency: string, spender: string, owner: Wallet) {
  await ZOO__factory.connect(currency, owner).approve(spender, MaxUint256)
}
export async function getBalance(currency: string, owner: string) {
  return ZOO__factory.connect(currency, deployerWallet).balanceOf(owner)
}

export function toNumWei(val: BigNumber) {
  return parseFloat(formatUnits(val, 'wei'))
}

export type EIP712Sig = {
  deadline: BigNumberish
  v: any
  r: any
  s: any
}

export async function signPermit(owner: Wallet, toAddress: string, tokenAddress: string, tokenId: number, chainId: number) {
  return new Promise<EIP712Sig>(async (res, reject) => {
    let nonce
    const mediaContract = Media__factory.connect(tokenAddress, owner)

    try {
      nonce = (await mediaContract.permitNonces(owner.address, tokenId)).toNumber()
    } catch (e) {
      console.error('NONCE', e)
      reject(e)
      return
    }

    const deadline = Math.floor(new Date().getTime() / 1000) + 60 * 60 * 24 // 24 hours
    const name = await mediaContract.name()

    try {
      const sig = signTypedData(Buffer.from(owner.privateKey.slice(2), 'hex'), {
        data: {
          types: {
            EIP712Domain: [
              { name: 'name', type: 'string' },
              { name: 'version', type: 'string' },
              { name: 'chainId', type: 'uint256' },
              { name: 'verifyingContract', type: 'address' },
            ],
            Permit: [
              { name: 'spender', type: 'address' },
              { name: 'tokenId', type: 'uint256' },
              { name: 'nonce', type: 'uint256' },
              { name: 'deadline', type: 'uint256' },
            ],
          },
          primaryType: 'Permit',
          domain: {
            name,
            version: '1',
            chainId,
            verifyingContract: mediaContract.address,
          },
          message: {
            spender: toAddress,
            tokenId,
            nonce,
            deadline,
          },
        },
      })
      const response = fromRpcSig(sig)
      res({
        r: response.r,
        s: response.s,
        v: response.v,
        deadline: deadline.toString(),
      })
    } catch (e) {
      console.error(e)
      reject(e)
    }
  })
}

export async function signMintWithSig(
  owner: Wallet,
  tokenAddress: string,
  creator: string,
  contentHash: string,
  metadataHash: string,
  creatorShare: BigNumberish,
  chainId: number,
) {
  return new Promise<EIP712Sig>(async (res, reject) => {
    let nonce
    const mediaContract = Media__factory.connect(tokenAddress, owner)

    try {
      nonce = (await mediaContract.mintWithSigNonces(creator)).toNumber()
    } catch (e) {
      console.error('NONCE', e)
      reject(e)
      return
    }

    const deadline = Math.floor(new Date().getTime() / 1000) + 60 * 60 * 24 // 24 hours
    const name = await mediaContract.name()

    try {
      const sig = signTypedData(Buffer.from(owner.privateKey.slice(2), 'hex'), {
        data: {
          types: {
            EIP712Domain: [
              { name: 'name', type: 'string' },
              { name: 'version', type: 'string' },
              { name: 'chainId', type: 'uint256' },
              { name: 'verifyingContract', type: 'address' },
            ],
            MintWithSig: [
              { name: 'contentHash', type: 'bytes32' },
              { name: 'metadataHash', type: 'bytes32' },
              { name: 'creatorShare', type: 'uint256' },
              { name: 'nonce', type: 'uint256' },
              { name: 'deadline', type: 'uint256' },
            ],
          },
          primaryType: 'MintWithSig',
          domain: {
            name,
            version: '1',
            chainId,
            verifyingContract: mediaContract.address,
          },
          message: {
            contentHash,
            metadataHash,
            creatorShare,
            nonce,
            deadline,
          },
        },
      })
      const response = fromRpcSig(sig)
      res({
        r: response.r,
        s: response.s,
        v: response.v,
        deadline: deadline.toString(),
      })
    } catch (e) {
      console.error(e)
      reject(e)
    }
  })
}

export const THOUSANDTH_ZOO = ethers.utils.parseUnits('0.001', 'ether') as BigNumber
export const TENTH_ZOO = ethers.utils.parseUnits('0.1', 'ether') as BigNumber
export const ONE_ZOO = ethers.utils.parseUnits('1', 'ether') as BigNumber
export const TWO_ZOO = ethers.utils.parseUnits('2', 'ether') as BigNumber

export const deployToken = async () => {
  return (await (await ethers.getContractFactory('ZOO')).deploy()) as ZOO
}

export const deployProtocol = async (tokenAddress) => {
  const [deployer] = await ethers.getSigners()
  const token = await (await new ZOO__factory(deployer).deploy()).deployed()
  // const drop = await (await new ZooDrop__factory(deployer).deploy()).deployed();
  const market = await (await new Market__factory(deployer).deploy()).deployed()
  const media = await (await new Media__factory(deployer).deploy('ANML', 'ZooAnimals')).deployed()
  const zookeeper = await (await new ZooKeeper__factory(deployer).deploy()).deployed()
  await market.configure(media.address)
  await media.configure(market.address)
  // await drop.configure(zookepeer, media);
  return { market, media }
}

export const deployOtherNFTs = async () => {
  const bad = (await (await ethers.getContractFactory('BadERC721')).deploy()) as BadERC721
  const test = (await (await ethers.getContractFactory('TestERC721')).deploy()) as TestERC721

  return { bad, test }
}

export const deployBidder = async (auction: string, nftContract: string) => {
  return (await (await (await ethers.getContractFactory('BadBidder')).deploy(auction, nftContract)).deployed()) as BadBidder
}

export const mint = async (media: Media) => {
  const metadataHex = ethers.utils.formatBytes32String('{}')
  const metadataHash = await sha256(metadataHex)
  const hash = ethers.utils.arrayify(metadataHash)
  await media.mint(
    {
      tokenURI: 'cryptozoo.co',
      metadataURI: 'cryptozoo.co',
      contentHash: hash,
      metadataHash: hash,
    },
    {
      prevOwner: Decimal.new(0),
      owner: Decimal.new(85),
      creator: Decimal.new(15),
    },
  )
}

export const approveAuction = async (media: Media, auctionHouse: Auction) => {
  await media.approve(auctionHouse.address, 0)
}

export const revert = (messages: TemplateStringsArray) => `VM Exception while processing transaction: revert ${messages[0]}`
