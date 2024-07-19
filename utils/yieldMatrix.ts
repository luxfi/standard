import { GoogleSpreadsheet } from 'google-spreadsheet'
import fs from 'fs'

import credentials from '../credentials.json'

// Load Lux rarity, animal and yield data from Google Sheet:
// https://docs.google.com/spreadsheets/d/14wCL5RYul5noZ6BhN2NUcYKaw23YwvcItm7bGG-O9ZM
;(async function () {
  const doc = new GoogleSpreadsheet('14wCL5RYul5noZ6BhN2NUcYKaw23YwvcItm7bGG-O9ZM')

  await doc.useServiceAccountAuth({
    client_email: credentials.client_email,
    private_key: credentials.private_key,
  })

  await doc.loadInfo()
  const sheet = doc.sheetsByIndex[0]

  // Get all Rarities
  const rarities = []
  await sheet.loadCells('C15:G30')
  ;[15, 19, 23, 27, 29].map((x) => {
    rarities.push({
      probability: sheet.getCellByA1(`C${x}`).value * 10000,
      name: sheet.getCellByA1(`D${x}`).value,
      yield: sheet.getCellByA1(`F${x}`).value,
      boost: sheet.getCellByA1(`G${x}`).value * 10000,
    })
  })

  fs.writeFileSync(__dirname + '/rarities.json', JSON.stringify(rarities))

  // Get Common Animals
  const animals = []
  await sheet.loadCells('E15:G30')
  ;[15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30].map((x) => {
    animals.push({
      name: sheet.getCellByA1(`E${x}`).value,
      rarity: sheet.getCellByA1(`D${x}`).value,
      yield: sheet.getCellByA1(`F${x}`).value,
      boost: sheet.getCellByA1(`G${x}`).value * 10000,
    })
  })

  animals.forEach((v, i) => {
    const slug = v.name.replaceAll(' ', '').toLowerCase()
    animals[i].tokenURI = `https://db.zoolabs.io/${slug}.jpg`
    animals[i].metadataURI = `https://db.zoolabs.io/${slug}.json`
    animals[i].yield = Math.round(animals[i].yield)
  })
  fs.writeFileSync(__dirname + '/animals.json', JSON.stringify(animals))

  // Get Common Hybrid animals
  let hybrids = []
  await sheet.loadCells('H15:W30')
  ;[15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30].map((x) => {
    hybrids = hybrids.concat([
      {
        rarity: 'Common',
        name: sheet.getCellByA1(`H${x}`).value,
        parentA: sheet.getCellByA1(`I${x}`).value,
        parentB: sheet.getCellByA1(`J${x}`).value,
        yield: sheet.getCellByA1(`K${x}`).value,
      },
      {
        rarity: 'Common',
        name: sheet.getCellByA1(`L${x}`).value,
        parentA: sheet.getCellByA1(`M${x}`).value,
        parentB: sheet.getCellByA1(`N${x}`).value,
        yield: sheet.getCellByA1(`O${x}`).value,
      },
      {
        rarity: 'Common',
        name: sheet.getCellByA1(`P${x}`).value,
        parentA: sheet.getCellByA1(`Q${x}`).value,
        parentB: sheet.getCellByA1(`R${x}`).value,
        yield: sheet.getCellByA1(`S${x}`).value,
      },
      {
        rarity: 'Common',
        name: sheet.getCellByA1(`T${x}`).value,
        parentA: sheet.getCellByA1(`U${x}`).value,
        parentB: sheet.getCellByA1(`V${x}`).value,
        yield: sheet.getCellByA1(`W${x}`).value,
      },
    ])
  })

  // Get Uncommon Hybrid animals
  await sheet.loadCells('Y15:AN30')
  ;[15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30].map((x) => {
    hybrids = hybrids.concat([
      {
        rarity: 'Uncommon',
        name: sheet.getCellByA1(`Y${x}`).value,
        parentA: sheet.getCellByA1(`Z${x}`).value,
        parentB: sheet.getCellByA1(`AA${x}`).value,
        yield: sheet.getCellByA1(`AB${x}`).value,
      },
      {
        rarity: 'Uncommon',
        name: sheet.getCellByA1(`AC${x}`).value,
        parentA: sheet.getCellByA1(`AD${x}`).value,
        parentB: sheet.getCellByA1(`AE${x}`).value,
        yield: sheet.getCellByA1(`AF${x}`).value,
      },
      {
        rarity: 'Uncommon',
        name: sheet.getCellByA1(`AG${x}`).value,
        parentA: sheet.getCellByA1(`AH${x}`).value,
        parentB: sheet.getCellByA1(`AI${x}`).value,
        yield: sheet.getCellByA1(`AJ${x}`).value,
      },
      {
        rarity: 'Uncommon',
        name: sheet.getCellByA1(`AK${x}`).value,
        parentA: sheet.getCellByA1(`AL${x}`).value,
        parentB: sheet.getCellByA1(`AM${x}`).value,
        yield: sheet.getCellByA1(`AN${x}`).value,
      },
    ])
  })

  // Get Rare Hybrid animals
  await sheet.loadCells('AP15:BE30')
  ;[15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30].map((x) => {
    hybrids = hybrids.concat([
      {
        rarity: 'Rare',
        name: sheet.getCellByA1(`AP${x}`).value,
        parentA: sheet.getCellByA1(`AQ${x}`).value,
        parentB: sheet.getCellByA1(`AR${x}`).value,
        yield: sheet.getCellByA1(`AS${x}`).value,
      },
      {
        rarity: 'Rare',
        name: sheet.getCellByA1(`AT${x}`).value,
        parentA: sheet.getCellByA1(`AU${x}`).value,
        parentB: sheet.getCellByA1(`AV${x}`).value,
        yield: sheet.getCellByA1(`AW${x}`).value,
      },
      {
        rarity: 'Rare',
        name: sheet.getCellByA1(`AX${x}`).value,
        parentA: sheet.getCellByA1(`AY${x}`).value,
        parentB: sheet.getCellByA1(`AZ${x}`).value,
        yield: sheet.getCellByA1(`BA${x}`).value,
      },
      {
        rarity: 'Rare',
        name: sheet.getCellByA1(`BB${x}`).value,
        parentA: sheet.getCellByA1(`BC${x}`).value,
        parentB: sheet.getCellByA1(`BD${x}`).value,
        yield: sheet.getCellByA1(`BE${x}`).value,
      },
    ])
  })

  // Get Super Rare Hybrid animals
  await sheet.loadCells('BG15:BN30')
  ;[15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30].map((x) => {
    hybrids = hybrids.concat([
      {
        rarity: 'Super Rare',
        name: sheet.getCellByA1(`BG${x}`).value,
        parentA: sheet.getCellByA1(`BH${x}`).value,
        parentB: sheet.getCellByA1(`BI${x}`).value,
        yield: sheet.getCellByA1(`BJ${x}`).value,
      },
      {
        rarity: 'Super Rare',
        name: sheet.getCellByA1(`BK${x}`).value,
        parentA: sheet.getCellByA1(`BL${x}`).value,
        parentB: sheet.getCellByA1(`BM${x}`).value,
        yield: sheet.getCellByA1(`BN${x}`).value,
      },
    ])
  })

  // Get Epic Hybrid animals
  await sheet.loadCells('BP15:BW30')
  ;[15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30].map((x) => {
    hybrids = hybrids.concat([
      {
        rarity: 'Epic',
        name: sheet.getCellByA1(`BP${x}`).value,
        parentA: sheet.getCellByA1(`BQ${x}`).value,
        parentB: sheet.getCellByA1(`BR${x}`).value,
        yield: sheet.getCellByA1(`BS${x}`).value,
      },
      {
        rarity: 'Epic',
        name: sheet.getCellByA1(`BT${x}`).value,
        parentA: sheet.getCellByA1(`BU${x}`).value,
        parentB: sheet.getCellByA1(`BV${x}`).value,
        yield: sheet.getCellByA1(`BW${x}`).value,
      },
    ])
  })

  hybrids.forEach((v, i) => {
    const slug = v.name.replaceAll(' ', '').toLowerCase()
    hybrids[i].tokenURI = `https://db.zoolabs.io/${slug}.jpg`
    hybrids[i].metadataURI = `https://db.zoolabs.io/${slug}.json`
    hybrids[i].yield = Math.round(hybrids[i].yield)
  })
  fs.writeFileSync(__dirname + '/hybrids.json', JSON.stringify(hybrids))
})()
