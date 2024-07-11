import { ethers } from 'hardhat'
import parse from 'csv-parse/lib/sync'
import assert from 'assert'
import fs from 'fs'

import ZOO from '../deployments/localhost/ZOO.json'

function chunks(arr, size) {
  const res = []
  for (let i = 0; i < arr.length; i += size) {
    const chunk = arr.slice(i, i + size)
    res.push(chunk)
  }
  return res
}

async function main() {
  throw new Error('Air drop done')

  const [signer]  = await ethers.getSigners()
  const zoo = await (await ethers.getContractAt('ZOO', ZOO.address)).connect(signer)

  const input = fs.readFileSync('holders.csv')

  // key_1: 'value 1', key_2: 'value 2'
  // address: 'amount'
  const records = parse(input, {
    columns: true,
    skip_empty_lines: true
  })

  // load in addresses
  let count = 0;
  const size = 420

  for (const chunk of chunks(records, size)) {
    const addresses = []
    const amounts   = []

    for (let i = 0; i < chunk.length; i++) {
      const row    = Object.values(chunk[i])
      const addr   = row[0]
      const amount = String(row[1]).replace(/[., ]/g, '').replace(/000$/g, '')

      if (Number(amount) == 0) continue

      try {
        addresses.push(addr)
        amounts.push(amount)
      } catch (e) {
        console.error(e)
      }
    }

    try {
      console.log(`Airdrop ${count+1} (${count*size}-${(count+1)*size})`)
      const tx = await zoo.airdrop(addresses, amounts)
      await tx.wait()
    } catch (e) {
      console.error(`Airdrop ${count} failed`, e)
    }

    count += 1
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
