#!/usr/bin/env node

import fs from 'fs'
import { ethers } from 'hardhat'

async function main() {

    const wallet = ethers.Wallet.createRandom()

    const out = {
        address: wallet.address,
        mnemonic: wallet.mnemonic.phrase,
        privateKey: wallet.privateKey,
    }

    console.log('Created wallet', out)

    fs.writeFileSync('wallet.json', JSON.stringify(out, null, 2))
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e)
    process.exit(-1)
  })
