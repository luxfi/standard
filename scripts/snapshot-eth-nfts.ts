#!/usr/bin/env npx ts-node
/**
 * Snapshot Ethereum NFT Holders for C-Chain Migration
 * 
 * Usage:
 *   ETH_RPC=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY npx ts-node scripts/snapshot-eth-nfts.ts
 * 
 * Output:
 *   - snapshots/lux-town-YYYY-MM-DD.json
 */

import { ethers } from 'ethers';
import * as fs from 'fs';
import * as path from 'path';

// Original Ethereum contract
const ETHEREUM_MEDIA = '0x31e0F919C67ceDd2Bc3E294340Dc900735810311';

// Minimal ERC721 ABI for snapshot
const ERC721_ABI = [
  'function name() view returns (string)',
  'function symbol() view returns (string)',
  'function totalSupply() view returns (uint256)',
  'function tokenByIndex(uint256 index) view returns (uint256)',
  'function ownerOf(uint256 tokenId) view returns (address)',
  'function tokenURI(uint256 tokenId) view returns (string)',
  'event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)',
];

// Extended ABI for Media contract (Zora-style)
const MEDIA_ABI = [
  ...ERC721_ABI,
  'function tokenContentHashes(uint256 tokenId) view returns (bytes32)',
  'function tokenMetadataHashes(uint256 tokenId) view returns (bytes32)',
  'function tokenMetadataURI(uint256 tokenId) view returns (string)',
  'function tokenCreators(uint256 tokenId) view returns (address)',
];

interface TokenData {
  tokenId: number;
  holder: string;
  creator: string;
  uri: string;
  contentHash: string;
  metadataHash: string;
  kind: number; // TokenType enum
  name: string;
}

interface Snapshot {
  contractAddress: string;
  network: string;
  blockNumber: number;
  timestamp: string;
  totalTokens: number;
  tokens: TokenData[];
}

async function main() {
  const rpcUrl = process.env.ETH_RPC || process.env.ETHEREUM_RPC_URL;
  
  if (!rpcUrl) {
    console.error('Error: Set ETH_RPC or ETHEREUM_RPC_URL environment variable');
    console.error('Example: ETH_RPC=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY');
    process.exit(1);
  }

  console.log('Connecting to Ethereum...');
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const network = await provider.getNetwork();
  const blockNumber = await provider.getBlockNumber();
  
  console.log(`Network: ${network.name} (chainId: ${network.chainId})`);
  console.log(`Block: ${blockNumber}`);
  console.log(`Contract: ${ETHEREUM_MEDIA}`);
  console.log('');

  const media = new ethers.Contract(ETHEREUM_MEDIA, MEDIA_ABI, provider);

  // Get basic info
  const name = await media.name();
  const symbol = await media.symbol();
  let totalSupply: bigint;
  
  try {
    totalSupply = await media.totalSupply();
  } catch (e) {
    // Fallback: count Transfer events
    console.log('totalSupply() not available, counting transfers...');
    const filter = media.filters.Transfer(ethers.ZeroAddress);
    const events = await media.queryFilter(filter, 0, 'latest');
    totalSupply = BigInt(events.length);
  }

  console.log(`Collection: ${name} (${symbol})`);
  console.log(`Total Supply: ${totalSupply}`);
  console.log('');

  const tokens: TokenData[] = [];
  const batchSize = 50;
  const total = Number(totalSupply);

  console.log('Fetching token data...');

  for (let i = 0; i < total; i += batchSize) {
    const end = Math.min(i + batchSize, total);
    console.log(`Processing tokens ${i + 1} to ${end}...`);

    const promises = [];
    for (let j = i; j < end; j++) {
      promises.push(fetchTokenData(media, j));
    }

    const results = await Promise.allSettled(promises);
    
    for (const result of results) {
      if (result.status === 'fulfilled' && result.value) {
        tokens.push(result.value);
      }
    }
  }

  console.log(`\nFetched ${tokens.length} tokens`);

  // Create snapshot
  const snapshot: Snapshot = {
    contractAddress: ETHEREUM_MEDIA,
    network: network.name || 'mainnet',
    blockNumber,
    timestamp: new Date().toISOString(),
    totalTokens: tokens.length,
    tokens,
  };

  // Save to file
  const snapshotsDir = path.join(__dirname, '..', 'snapshots');
  if (!fs.existsSync(snapshotsDir)) {
    fs.mkdirSync(snapshotsDir, { recursive: true });
  }

  const date = new Date().toISOString().split('T')[0];
  const filename = `lux-town-${date}.json`;
  const filepath = path.join(snapshotsDir, filename);

  fs.writeFileSync(filepath, JSON.stringify(snapshot, null, 2));
  console.log(`\nSnapshot saved to: ${filepath}`);

  // Also generate migration calldata
  await generateMigrationData(snapshot, snapshotsDir);
}

async function fetchTokenData(media: ethers.Contract, index: number): Promise<TokenData | null> {
  try {
    let tokenId: bigint;
    
    try {
      tokenId = await media.tokenByIndex(index);
    } catch {
      tokenId = BigInt(index + 1); // Fallback to 1-indexed
    }

    const [holder, uri] = await Promise.all([
      media.ownerOf(tokenId),
      media.tokenURI(tokenId).catch(() => ''),
    ]);

    let contentHash = ethers.ZeroHash;
    let metadataHash = ethers.ZeroHash;
    let creator = holder;

    try {
      [contentHash, metadataHash, creator] = await Promise.all([
        media.tokenContentHashes(tokenId).catch(() => ethers.ZeroHash),
        media.tokenMetadataHashes(tokenId).catch(() => ethers.ZeroHash),
        media.tokenCreators(tokenId).catch(() => holder),
      ]);
    } catch {
      // Legacy contract might not have these
    }

    return {
      tokenId: Number(tokenId),
      holder,
      creator,
      uri,
      contentHash: contentHash.toString(),
      metadataHash: metadataHash.toString(),
      kind: 0, // Default to VALIDATOR type
      name: `Lux Town #${tokenId}`,
    };
  } catch (e) {
    console.error(`Error fetching token ${index}:`, e);
    return null;
  }
}

async function generateMigrationData(snapshot: Snapshot, outputDir: string) {
  console.log('\nGenerating migration calldata...');

  // Split into batches of 50 for gas efficiency
  const batchSize = 50;
  const batches: TokenData[][] = [];

  for (let i = 0; i < snapshot.tokens.length; i += batchSize) {
    batches.push(snapshot.tokens.slice(i, i + batchSize));
  }

  // Generate calldata for each batch
  const migrationData = {
    contractAddress: snapshot.contractAddress,
    timestamp: snapshot.timestamp,
    totalBatches: batches.length,
    batches: batches.map((batch, index) => ({
      batchIndex: index,
      tokenCount: batch.length,
      holders: batch.map(t => t.holder),
      originTokenIds: batch.map(t => t.tokenId),
      uris: batch.map(t => t.uri),
      contentHashes: batch.map(t => t.contentHash),
      metadataHashes: batch.map(t => t.metadataHash),
      kinds: batch.map(t => t.kind),
      names: batch.map(t => t.name),
    })),
  };

  const date = new Date().toISOString().split('T')[0];
  const filename = `lux-town-migration-${date}.json`;
  const filepath = path.join(outputDir, filename);

  fs.writeFileSync(filepath, JSON.stringify(migrationData, null, 2));
  console.log(`Migration data saved to: ${filepath}`);
  console.log(`Total batches: ${batches.length} (${batchSize} tokens per batch)`);
}

main().catch(console.error);
