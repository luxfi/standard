import { Currency, NativeCurrency, Token } from "@uniswap/sdk-core";
import { CHAINS } from "../chains/chains";

export interface IToken {
    name: string;
    asset: string;
    logo: string;
    contract_address: string;
    decimals: number;
    status: string;
    is_deposit_enabled: boolean;
    is_withdrawal_enabled: boolean;
    is_refuel_enabled: boolean;
    max_withdrawal_amount: number;
    deposit_fee: number;
    withdrawal_fee: number;
    source_base_fee: number;
    destination_base_fee: number;
    is_native: boolean;
};

export const sdkTokenFromToken = (chainId: number, token: IToken): Token => {
    return new Token(chainId, token.contract_address, token.decimals, token.asset, token.name);
}

function isLux(chainId: number): boolean {
    return chainId === CHAINS.MAINNET || chainId === CHAINS.TESTNET;
}

export const WRAPPED_NATIVE_CURRENCY: { [chainId: number]: Token | undefined } = {
    [CHAINS.MAINNET]: new Token(
      CHAINS.MAINNET,
      '0x53B1aAA5b6DDFD4eD00D0A7b5Ef333dc74B605b5',
      18,
      'WLUX',
      'Lux native asset'
    ),
    [CHAINS.TESTNET]: new Token(
        CHAINS.TESTNET,
        '0x0650683db720c793ff7e609A08b5fc2792c91f39',
        18,
        'WLUX',
        'Lux native asset'
    ),
  }

class LuxNativeCurrency extends NativeCurrency {
    equals(other: Currency): boolean {
      return other.isNative && other.chainId === this.chainId
    }
  
    get wrapped(): Token {
      if (!isLux(this.chainId)) throw new Error('Not lux')
      const wrapped = WRAPPED_NATIVE_CURRENCY[this.chainId]
      if(!wrapped) {
        throw new Error('No wrapped native currency for this chain');
      }

      return wrapped
    }
  
    public constructor(chainId: number) {
      if (!isLux(chainId)) throw new Error('Not lux')
      super(chainId, 18, 'LUX', 'Lux')
    }
  }

export const NO_TOKEN: IToken = {
    name: "NO_TOKEN_01",
    asset: "",
    logo: "",
    contract_address: "",
    decimals: 0,
    status: "",
    is_deposit_enabled: false,
    is_withdrawal_enabled: false,
    is_refuel_enabled: false,
    max_withdrawal_amount: 0,
    deposit_fee: 0,
    withdrawal_fee: 0,
    source_base_fee: 0,
    destination_base_fee: 0,
    is_native: false,
}

export const LUX_CURRENCY_MAINNET = new LuxNativeCurrency(CHAINS.MAINNET);
export const LUX_CURRENCY_TESTNET = new LuxNativeCurrency(CHAINS.TESTNET);