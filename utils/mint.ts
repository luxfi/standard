import { ChainId } from '@luxdefi/sdk'
import { BigNumberish } from '@ethersproject/bignumber'
import { getAsk } from './ask'
import queryString from 'query-string'
import _ from 'lodash'

enum TokenType {
  VALIDATOR = 0,
  CREDIT = 1,
  COIN = 2,
  PASS = 3,
  URANIUM = 4,
  VALIDATOR_MINI = 5,
}

const TOKEN_TYPES = {
  [TokenType.COIN]: 'coin',
  [TokenType.CREDIT]: 'credit',
  [TokenType.PASS]: 'pass',
  [TokenType.URANIUM]: 'uranium',
  [TokenType.VALIDATOR]: 'validator',
  [TokenType.VALIDATOR_MINI]: 'mini',
}

const TOKEN_URI = {
  [TokenType.COIN]: 'https://lux.town/api/token/coin.json',
  [TokenType.CREDIT]: 'https://lux.town/api/token/credit.json',
  [TokenType.PASS]: 'https://lux.town/api/token/pass.json',
  [TokenType.URANIUM]: 'https://lux.town/api/token/uranium.json',
  [TokenType.VALIDATOR]: 'https://lux.town/api/token/validator.json',
  [TokenType.VALIDATOR_MINI]: 'https://lux.town/api/token/mini.json',
}

const METADATA_URI = {
  [TokenType.COIN]: 'https://lux.town/api/metadata/coin.json',
  [TokenType.CREDIT]: 'https://lux.town/api/metadata/credit.json',
  [TokenType.PASS]: 'https://lux.town/api/metadata/pass.json',
  [TokenType.URANIUM]: 'https://lux.town/api/metadata/uranium.json',
  [TokenType.VALIDATOR]: 'https://lux.town/api/metadata/validator.json',
  [TokenType.VALIDATOR_MINI]: 'https://lux.town/api/metadata/mini.json',
}

const CHAIN_IDS = {
  mainnet: ChainId.MAINNET,
  testnet: ChainId.ROPSTEN,
  hardhat: ChainId.HARDHAT,
  localhost: ChainId.HARDHAT,
}

type QueryString = {
  [key: string]: string | number
}

type TokenTypeInput = {
  kind: number
  name: string
  supply: number
  queryString: QueryString,
  ask: {
    currency: string
    amount: BigNumberish
    offline: boolean
  }
}

const MILLION = 1000000
const HUNDREDK = 100000

const wait = async (ms: number) => {
  return new Promise((resolve) => setTimeout(() => resolve(true), ms))
}

const getTokenTypes = (network: string, mainnetTokenTypes: TokenTypeInput[], testTokenTypes: TokenTypeInput[]) => {
  return (network === 'mainnet' ? mainnetTokenTypes : testTokenTypes).map((t) => {
    const q = {
      name: `__${_.snakeCase(t.name)}__`,
      type: `__${TOKEN_TYPES[t.kind]}__`,
      ...t.queryString
    }
    return {
      ...t,
      tokenURI: `${TOKEN_URI[t.kind]}?${queryString.stringify(q)}`,
      metadataURI: `${METADATA_URI[t.kind]}?${queryString.stringify(q)}`,
    }
  })
}

const chunkQuantity = (number: number, n: number) => {
  var chunks: number[] = Array(Math.floor(number / n)).fill(n)
  var remainder = number % n

  if (remainder > 0) {
    chunks.push(remainder)
  }
  return chunks
}

// Configure game for our Gen 0 drop
export default async function mint(app: any, drop: any, network: string = 'hardhat') {
  const chainId = CHAIN_IDS[network]

  console.log({ network, chainId })

  // Validator 100
  // Wallet
  // - 10B Lux x 1
  // - 1B Lux x 10
  // - 100M Lux x 100
  // - 10M Lux x1000
  // - 1M Lux x10000
  // CREDIT 1000

  const mainnetTokenTypes = [
    {
      kind: TokenType.VALIDATOR,
      name: 'Validator',
      ask: getAsk(chainId, 'USDT', `${MILLION}`),
      supply: 100,
      queryString: {}
    },
    {
      kind: TokenType.VALIDATOR_MINI,
      name: 'Mini',
      ask: getAsk(chainId, 'USDT', `${HUNDREDK}`),
      supply: 1000,
      queryString: {}
    },
    {
      kind: TokenType.COIN,
      name: '10B Coin',
      ask: getAsk(chainId, 'USDT', `21000000`),
      supply: 1,
      queryString: {
        lux: 10000000000000,
      }
    },
    {
      kind: TokenType.COIN,
      name: '1B Coin',
      ask: getAsk(chainId, 'USDT', `2100000`),
      supply: 10,
      queryString: {
        lux: 1000 * MILLION,
      }
    },
    {
      kind: TokenType.COIN,
      name: '100M Coin',
      ask: getAsk(chainId, 'USDT', `210000`),
      supply: 100,
      queryString: {
        lux: 100 * MILLION,
      }
    },
    {
      kind: TokenType.COIN,
      name: '10M Coin',
      ask: getAsk(chainId, 'USDT', `21000`),
      supply: 1000,
      queryString: {
        lux: 10 * MILLION,
      }
    },
    {
      kind: TokenType.COIN,
      name: '1M Coin',
      ask: getAsk(chainId, 'USDT', `2100`),
      supply: 10000,
      queryString: {
        lux: MILLION,
      }
    },
    {
      kind: TokenType.CREDIT,
      name: 'Founder Card',
      ask: getAsk(chainId, 'USDT', `${MILLION}`),
      supply: 100,
      queryString: {}
    },
    {
      kind: TokenType.CREDIT,
      name: 'Executive Card',
      ask: getAsk(chainId, 'USDT', `${HUNDREDK}`),
      supply: 1000,
      queryString: {}
    },
    {
      kind: TokenType.CREDIT,
      name: 'Black Card',
      ask: getAsk(chainId, 'USDT', `9999`),
      supply: 10000,
      queryString: {}
    },
    {
      kind: TokenType.CREDIT,
      name: 'Lux Card',
      ask: getAsk(chainId, 'USDT', `999`),
      supply: 100000,
      queryString: {}
    },
    {
      kind: TokenType.URANIUM,
      name: 'Uranium (1 Pound)',
      ask: getAsk(chainId, 'USDT', `45`),
      supply: 1000000,
      queryString: {}
    },
    {
      kind: TokenType.URANIUM,
      name: 'Uranium (10 Pound)',
      ask: getAsk(chainId, 'USDT', `450`),
      supply: 100000,
      queryString: {}
    },
    {
      kind: TokenType.URANIUM,
      name: 'Uranium (100 Pound)',
      ask: getAsk(chainId, 'USDT', `4500`),
      supply: 10000,
      queryString: {}
    },
    {
      kind: TokenType.URANIUM,
      name: 'Uranium (1000 Pound)',
      ask: getAsk(chainId, 'USDT', `45000`),
      supply: 1000,
      queryString: {}
    },
    {
      kind: TokenType.URANIUM,
      name: 'Uranium (1 Ton)',
      ask: getAsk(chainId, 'USDT', `90000`),
      supply: 100,
      queryString: {}
    },
    {
      kind: TokenType.URANIUM,
      name: 'Uranium (10 Ton)',
      ask: getAsk(chainId, 'USDT', `900000`),
      supply: 10,
      queryString: {}
    },
    {
      kind: TokenType.URANIUM,
      name: 'Uranium (100 Ton)',
      ask: getAsk(chainId, 'USDT', `9000000`),
      supply: 1,
      queryString: {}
    },
    {
      kind: TokenType.URANIUM,
      name: 'Uranium (1000 Ton)',
      ask: getAsk(chainId, 'USDT', `90000000`),
      supply: 1,
      queryString: {}
    },
  ]

  // Add tokenType
  const testTokenTypes = [
    {
      kind: TokenType.VALIDATOR,
      name: 'Validator',
      ask: getAsk(chainId, 'USDT', `${MILLION}`),
      supply: 100,
      queryString: {}
    },
    {
      kind: TokenType.COIN,
      name: '10B Coin',
      ask: getAsk(chainId, 'USDT', `21000000`),
      supply: 1,
      queryString: {
        lux: 10000000000000,
      }
    },
    {
      kind: TokenType.COIN,
      name: '1B Coin',
      ask: getAsk(chainId, 'USDT', `2100000`),
      supply: 10,
      queryString: {
        lux: 1000 * MILLION,
      }
    },
    {
      kind: TokenType.COIN,
      name: '100M Coin',
      ask: getAsk(chainId, 'USDT', `210000`),
      supply: 100,
      queryString: {
        lux: 100 * MILLION,
      }
    },
    {
      kind: TokenType.COIN,
      name: '10M Coin',
      ask: getAsk(chainId, 'USDT', `21000`),
      supply: 1000,
      queryString: {
        lux: 10 * MILLION,
      }
    },
    {
      kind: TokenType.COIN,
      name: '1M Coin',
      ask: getAsk(chainId, 'ETH', `15`),
      supply: 10000,
      queryString: {
        lux: MILLION,
      }
    },
    {
      kind: TokenType.CREDIT,
      name: 'Credit Card',
      ask: getAsk(chainId, 'USDT', `${MILLION}`),
      supply: 1000,
      queryString: {}
    },
    {
      kind: TokenType.PASS,
      name: 'Pass',
      ask: getAsk(chainId, 'USDT', `99`),
      supply: 10000,
      queryString: {}
    },
  ]

  const tokenTypes = getTokenTypes(network, mainnetTokenTypes, testTokenTypes)

  for (const t of tokenTypes) {

    const existingTokenType = await drop.getTokenType(t.name)

    if (!existingTokenType.name) {
      console.log('Drop.setTokenType', t.kind, t.name, t.ask, t.supply, t.tokenURI, t.metadataURI)
      const tx = await drop.setTokenType(t.kind, t.name, t.ask, t.supply, t.tokenURI, t.metadataURI)
      await tx.wait()
    }
  }

  const configuredTypes = await drop.getTokenTypes()

  if (configuredTypes.length > 0) {
    console.log('Drop: Token types')
    configuredTypes.forEach((configureType) => {
      console.log(`- ${configureType.name}`)
    })
  }

  console.log('Done')
}
