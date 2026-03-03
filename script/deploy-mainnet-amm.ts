/**
 * Deploy AMM contracts to Lux Mainnet C-Chain (96369)
 *
 * Deploys: WLUX, LETH, LBTC, LUSDC, AMMV2Factory, AMMV2Router
 * Creates pools: WLUX/LUSDC, WLUX/LETH, WLUX/LBTC
 *
 * Usage:
 *   LUX_PRIVATE_KEY=0x... bun run ~/work/lux/standard/script/deploy-mainnet-amm.ts
 *
 * The deployer must have sufficient LUX for gas + initial liquidity wrapping.
 */

import { createWalletClient, createPublicClient, http, parseEther, parseUnits, formatEther, defineChain } from 'viem'
import { privateKeyToAccount, mnemonicToAccount } from 'viem/accounts'
import type { Hex, Address, PublicClient, WalletClient, Account } from 'viem'
import * as fs from 'fs'
import * as path from 'path'

// ---- Config ----

const RPC_URL = 'https://api.lux.network/mainnet/ext/bc/C/rpc'
const CHAIN_ID = 96369

const luxMainnet = defineChain({
  id: CHAIN_ID,
  name: 'Lux Mainnet',
  nativeCurrency: { name: 'LUX', symbol: 'LUX', decimals: 18 },
  rpcUrls: {
    default: { http: [RPC_URL] },
  },
  blockExplorers: {
    default: { name: 'Lux Explorer', url: 'https://explore.lux.network' },
  },
})

// Forge artifact paths
const STANDARD_PATH = path.join(process.env.HOME || '', 'work', 'lux', 'standard')
const ARTIFACTS: Record<string, { folder: string; file: string }> = {
  WLUX: { folder: 'WLUX.sol', file: 'WLUX.json' },
  LETH: { folder: 'ETH.sol', file: 'BridgedETH.json' },
  LBTC: { folder: 'BTC.sol', file: 'BridgedBTC.json' },
  LUSDC: { folder: 'USDC.sol', file: 'BridgedUSDC.json' },
  AMMV2Factory: { folder: 'AMMV2Factory.sol', file: 'AMMV2Factory.json' },
  AMMV2Router: { folder: 'AMMV2Router.sol', file: 'AMMV2Router.json' },
}

// ---- Helpers ----

function loadArtifact(name: string): { abi: any[]; bytecode: Hex } {
  const mapping = ARTIFACTS[name]
  if (!mapping) throw new Error(`Unknown contract: ${name}`)
  const artifactPath = path.join(STANDARD_PATH, 'out', mapping.folder, mapping.file)
  if (!fs.existsSync(artifactPath)) {
    throw new Error(`Artifact not found: ${artifactPath}. Run 'forge build' in ~/work/lux/standard/`)
  }
  const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf-8'))
  return { abi: artifact.abi, bytecode: artifact.bytecode.object as Hex }
}

async function deployContract(
  walletClient: WalletClient,
  publicClient: PublicClient,
  artifact: { abi: any[]; bytecode: Hex },
  args: any[],
): Promise<Address> {
  const hash = await walletClient.deployContract({
    abi: artifact.abi,
    bytecode: artifact.bytecode,
    args,
    chain: luxMainnet,
    account: walletClient.account!,
  })
  console.log(`  tx: ${hash}`)
  const receipt = await publicClient.waitForTransactionReceipt({ hash, timeout: 120_000 })
  if (receipt.status !== 'success') throw new Error(`Deploy failed: ${hash}`)
  if (!receipt.contractAddress) throw new Error(`No contract address: ${hash}`)
  return receipt.contractAddress
}

async function sendAndWait(
  walletClient: WalletClient,
  publicClient: PublicClient,
  args: any,
): Promise<void> {
  const hash = await walletClient.writeContract({
    ...args,
    chain: luxMainnet,
    account: walletClient.account!,
  })
  const receipt = await publicClient.waitForTransactionReceipt({ hash, timeout: 120_000 })
  if (receipt.status !== 'success') throw new Error(`Tx failed: ${hash}`)
}

// ---- Main ----

async function main() {
  const privateKey = process.env.LUX_PRIVATE_KEY
  const mnemonic = process.env.LUX_MNEMONIC
  if (!privateKey && !mnemonic) {
    console.error('ERROR: LUX_PRIVATE_KEY or LUX_MNEMONIC env var required')
    console.error('Usage: LUX_PRIVATE_KEY=0x... bun run script/deploy-mainnet-amm.ts')
    console.error('   or: LUX_MNEMONIC="word1 word2 ..." bun run script/deploy-mainnet-amm.ts')
    process.exit(1)
  }

  const account = privateKey
    ? privateKeyToAccount(privateKey as Hex)
    : mnemonicToAccount(mnemonic!)
  console.log(`Deployer: ${account.address}`)

  const publicClient = createPublicClient({
    chain: luxMainnet,
    transport: http(RPC_URL, { timeout: 120_000 }),
  })

  const walletClient = createWalletClient({
    account,
    chain: luxMainnet,
    transport: http(RPC_URL, { timeout: 120_000 }),
  })

  // Check balance
  const balance = await publicClient.getBalance({ address: account.address })
  console.log(`Balance: ${formatEther(balance)} LUX`)
  if (balance < parseEther('10')) {
    console.error('Need at least 10 LUX for deployment + liquidity')
    process.exit(1)
  }

  const nonce = await publicClient.getTransactionCount({ address: account.address })
  console.log(`Nonce: ${nonce}`)

  // Check chain ID
  const chainId = await publicClient.getChainId()
  console.log(`Chain ID: ${chainId}`)
  if (chainId !== CHAIN_ID) {
    console.error(`Wrong chain! Expected ${CHAIN_ID}, got ${chainId}`)
    process.exit(1)
  }

  console.log('\n=== Phase 1: Core Tokens ===')

  console.log('Deploying WLUX...')
  const wlux = await deployContract(walletClient, publicClient, loadArtifact('WLUX'), [])
  console.log(`  WLUX: ${wlux}`)

  console.log('Deploying LETH (BridgedETH)...')
  const leth = await deployContract(walletClient, publicClient, loadArtifact('LETH'), [])
  console.log(`  LETH: ${leth}`)

  console.log('Deploying LBTC (BridgedBTC)...')
  const lbtc = await deployContract(walletClient, publicClient, loadArtifact('LBTC'), [])
  console.log(`  LBTC: ${lbtc}`)

  console.log('Deploying LUSDC (BridgedUSDC)...')
  const lusdc = await deployContract(walletClient, publicClient, loadArtifact('LUSDC'), [])
  console.log(`  LUSDC: ${lusdc}`)

  console.log('\n=== Phase 2: AMM ===')

  console.log('Deploying AMMV2Factory...')
  const factory = await deployContract(walletClient, publicClient, loadArtifact('AMMV2Factory'), [account.address])
  console.log(`  Factory: ${factory}`)

  console.log('Deploying AMMV2Router...')
  const router = await deployContract(walletClient, publicClient, loadArtifact('AMMV2Router'), [factory, wlux])
  console.log(`  Router: ${router}`)

  console.log('\n=== Phase 3: Mint Tokens ===')

  const { abi: mintAbi } = loadArtifact('LETH')

  console.log('Minting 10 LETH...')
  await sendAndWait(walletClient, publicClient, {
    address: leth,
    abi: mintAbi,
    functionName: 'mint',
    args: [account.address, parseEther('10')],
  })

  console.log('Minting 1 LBTC...')
  await sendAndWait(walletClient, publicClient, {
    address: lbtc,
    abi: mintAbi,
    functionName: 'mint',
    args: [account.address, parseUnits('1', 8)],
  })

  console.log('Minting 100,000 LUSDC...')
  await sendAndWait(walletClient, publicClient, {
    address: lusdc,
    abi: mintAbi,
    functionName: 'mint',
    args: [account.address, parseUnits('100000', 6)],
  })

  console.log('Wrapping 100 LUX...')
  const { abi: wluxAbi } = loadArtifact('WLUX')
  await sendAndWait(walletClient, publicClient, {
    address: wlux,
    abi: wluxAbi,
    functionName: 'deposit',
    value: parseEther('100'),
  })

  console.log('\n=== Phase 4: Create Liquidity Pools ===')

  const { abi: routerAbi } = loadArtifact('AMMV2Router')
  const { abi: factoryAbi } = loadArtifact('AMMV2Factory')
  const maxApproval = parseEther('1000000000')
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600)

  console.log('Approving tokens...')
  for (const token of [wlux, leth, lbtc, lusdc]) {
    await sendAndWait(walletClient, publicClient, {
      address: token,
      abi: [{ name: 'approve', type: 'function', inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }], stateMutability: 'nonpayable' }],
      functionName: 'approve',
      args: [router, maxApproval],
    })
  }

  // WLUX/LUSDC: 50 WLUX + 250 LUSDC ($5/LUX)
  console.log('Creating WLUX/LUSDC pool (50 WLUX + 250 LUSDC)...')
  await sendAndWait(walletClient, publicClient, {
    address: router,
    abi: routerAbi,
    functionName: 'addLiquidity',
    args: [wlux, lusdc, parseEther('50'), parseUnits('250', 6), 0n, 0n, account.address, deadline],
  })

  // WLUX/LETH: 30 WLUX + 1 LETH (30 LUX/ETH)
  console.log('Creating WLUX/LETH pool (30 WLUX + 1 LETH)...')
  await sendAndWait(walletClient, publicClient, {
    address: router,
    abi: routerAbi,
    functionName: 'addLiquidity',
    args: [wlux, leth, parseEther('30'), parseEther('1'), 0n, 0n, account.address, deadline],
  })

  // WLUX/LBTC: 20 WLUX + 0.01 LBTC (2000 LUX/BTC)
  console.log('Creating WLUX/LBTC pool (20 WLUX + 0.01 LBTC)...')
  await sendAndWait(walletClient, publicClient, {
    address: router,
    abi: routerAbi,
    functionName: 'addLiquidity',
    args: [wlux, lbtc, parseEther('20'), parseUnits('0.01', 8), 0n, 0n, account.address, deadline],
  })

  // Get pool addresses
  const wluxLusdcPool = await publicClient.readContract({
    address: factory,
    abi: factoryAbi,
    functionName: 'getPair',
    args: [wlux, lusdc],
  }) as Address

  const wluxLethPool = await publicClient.readContract({
    address: factory,
    abi: factoryAbi,
    functionName: 'getPair',
    args: [wlux, leth],
  }) as Address

  const wluxLbtcPool = await publicClient.readContract({
    address: factory,
    abi: factoryAbi,
    functionName: 'getPair',
    args: [wlux, lbtc],
  }) as Address

  console.log('\n========================================')
  console.log('  DEPLOYMENT COMPLETE')
  console.log('========================================')
  console.log('')
  console.log('CORE TOKENS:')
  console.log(`  WLUX:   ${wlux}`)
  console.log(`  LETH:   ${leth}`)
  console.log(`  LBTC:   ${lbtc}`)
  console.log(`  LUSDC:  ${lusdc}`)
  console.log('')
  console.log('AMM:')
  console.log(`  Factory: ${factory}`)
  console.log(`  Router:  ${router}`)
  console.log('')
  console.log('POOLS:')
  console.log(`  WLUX/LUSDC: ${wluxLusdcPool}`)
  console.log(`  WLUX/LETH:  ${wluxLethPool}`)
  console.log(`  WLUX/LBTC:  ${wluxLbtcPool}`)
  console.log('')

  // Output JSON for easy config update
  const result = {
    chainId: CHAIN_ID,
    deployer: account.address,
    contracts: {
      WLUX: wlux,
      LETH: leth,
      LBTC: lbtc,
      LUSDC: lusdc,
      AMMV2Factory: factory,
      AMMV2Router: router,
    },
    pools: {
      'WLUX/LUSDC': wluxLusdcPool,
      'WLUX/LETH': wluxLethPool,
      'WLUX/LBTC': wluxLbtcPool,
    },
  }

  const outPath = path.join(STANDARD_PATH, 'deployments', `mainnet-${CHAIN_ID}-${Date.now()}.json`)
  fs.mkdirSync(path.dirname(outPath), { recursive: true })
  fs.writeFileSync(outPath, JSON.stringify(result, null, 2))
  console.log(`Saved to: ${outPath}`)
}

main().catch((err) => {
  console.error('DEPLOYMENT FAILED:', err.message || err)
  process.exit(1)
})
