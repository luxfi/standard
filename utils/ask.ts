import { ChainId, Token, getSymbolCurrencyMap } from '@luxdefi/sdk'
import { ethers } from 'hardhat'
import contracts from '../contracts.json'

export const ASK_ETH = '0x0000000000000000000000000000000000000000'

export const getSymbolCurrency = (chainId: ChainId, symbol: string): Token => {
  const map = getSymbolCurrencyMap(contracts)
  return map[chainId.toString()][symbol]
}

export const getAsk = (chainId: ChainId, symbol: string, amount: string, offline: boolean = false) => {
  const currency: Token = getSymbolCurrency(chainId, symbol)
  return {
    currency: ['ETH'].includes(symbol) ? ASK_ETH : currency.address,
    amount: ethers.utils.parseUnits(amount, currency.decimals),
    offline,
  }
}
