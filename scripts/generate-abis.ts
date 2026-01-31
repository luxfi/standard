#!/usr/bin/env npx ts-node
/**
 * Generate TypeScript ABI exports from compiled Foundry artifacts
 * Run: npx ts-node scripts/generate-abis.ts
 */

import fs from 'fs'
import path from 'path'

const OUT_DIR = path.join(__dirname, '..', 'out')
const ABI_DIR = path.join(__dirname, '..', 'contracts', 'abi')

// Contracts to export ABIs for
const GOVERNANCE_CONTRACTS = [
  'Governor',
  'Strategy',
  'Controller',
  'SubDAO',
  'Timelock',
  'VotesToken',
  'Vote',
  'GaugeController',
  'vLUX',
  'Karma',
]

const SAFE_CONTRACTS = [
  'FreezeGuard',
  'FreezeVoting',
]

function getAbi(contractName: string): any[] | null {
  const jsonPath = path.join(OUT_DIR, `${contractName}.sol`, `${contractName}.json`)
  if (!fs.existsSync(jsonPath)) {
    console.warn(`Warning: ${jsonPath} not found`)
    return null
  }
  const json = JSON.parse(fs.readFileSync(jsonPath, 'utf-8'))
  return json.abi
}

function generateAbiFile(contracts: string[], outputName: string) {
  const exports: string[] = []

  for (const contract of contracts) {
    const abi = getAbi(contract)
    if (abi) {
      exports.push(`export const ${contract}Abi = ${JSON.stringify(abi, null, 2)} as const`)
    }
  }

  const content = `// Auto-generated from @luxfi/standard compiled artifacts
// Do not edit manually - run \`npm run build:abi\` to regenerate

${exports.join('\n\n')}
`

  const outputPath = path.join(ABI_DIR, `${outputName}.ts`)
  fs.mkdirSync(ABI_DIR, { recursive: true })
  fs.writeFileSync(outputPath, content)
  console.log(`Generated ${outputPath}`)
}

// Generate index
function generateIndex() {
  const content = `// @luxfi/standard ABI exports
export * from './governance'
export * from './safe'
`
  fs.writeFileSync(path.join(ABI_DIR, 'index.ts'), content)
  console.log(`Generated ${path.join(ABI_DIR, 'index.ts')}`)
}

// Main
generateAbiFile(GOVERNANCE_CONTRACTS, 'governance')
generateAbiFile(SAFE_CONTRACTS, 'safe')
generateIndex()
console.log('Done!')
