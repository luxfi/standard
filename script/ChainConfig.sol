// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ChainConfig
/// @notice Chain-specific token addresses and protocol configurations
/// @dev Contains deployed addresses for Lux, Zoo, and Hanzo chains
library ChainConfig {
    // ═══════════════════════════════════════════════════════════════════════════
    // Chain IDs
    // ═══════════════════════════════════════════════════════════════════════════
    
    uint256 constant LUX_MAINNET = 96369;
    uint256 constant LUX_TESTNET = 96368;
    uint256 constant ZOO_MAINNET = 200200;
    uint256 constant HANZO_MAINNET = 36963;
    uint256 constant LOCAL = 31337;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // Treasury / Multisig
    // ═══════════════════════════════════════════════════════════════════════════
    
    address constant TREASURY = 0x9011E888251AB053B7bD1cdB598Db4f9DEd94714;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // Lux Mainnet (96369) - Bridge Tokens
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Native wrapped LUX
    address constant LUX_WLUX = 0x4888E4a2Ee0F03051c72D2BD3ACf755eD3498B3E;
    
    // Stablecoins (teleport-minted from other chains)
    address constant LUX_LUSD = 0x848Cff46eb323f323b6Bbe1Df274E40793d7f2c2;  // Lux USD
    
    // Major cryptos (teleport-minted from other chains)
    address constant LUX_LBTC = 0x1E48D32a4F5e9f08DB9aE4959163300FaF8A6C8e;  // Lux BTC
    address constant LUX_LETH = 0x60E0a8167FC13dE89348978860466C9ceC24B9ba;  // Lux ETH
    address constant LUX_LBNB = 0x6EdcF3645DeF09DB45050638c41157D8B9FEa1cf;  // Lux BNB
    address constant LUX_LPOL = 0x28BfC5DD4B7E15659e41190983e5fE3df1132bB9;  // Lux POL
    address constant LUX_LCELO = 0x3078847F879A33994cDa2Ec1540ca52b5E0eE2e5; // Lux CELO
    address constant LUX_LFTM = 0x8B982132d639527E8a0eAAD385f97719af8f5e04;  // Lux FTM
    address constant LUX_LXDAI = 0x7dfb3cBf7CF9c96fd56e3601FBA50AF45C731211; // Lux xDAI
    address constant LUX_LSOL = 0x26B40f650156C7EbF9e087Dd0dca181Fe87625B7;  // Lux SOL
    address constant LUX_LTON = 0x3141b94b89691009b950c96e97Bff48e0C543E3C;  // Lux TON
    address constant LUX_LAVAX = 0x0e4bD0DD67c15dECfBBBdbbE07FC9d51D737693D; // Lux AVAX
    address constant LUX_LBLAST = 0x94f49D0F4C62bbE4238F4AaA9200287bea9F2976; // Lux BLAST
    
    // Cross-chain tokens
    address constant LUX_LZOO = 0x5E5290f350352768bD2bfC59c2DA15DD04A7cB88;  // Lux ZOO
    
    // Meme tokens (teleport-minted)
    address constant LUX_LBONK = 0x8c72230C7aBA4F2F5bA8C3A2Ad0f03DC09A1E829;
    address constant LUX_LWIF = 0x1b95e5cB80e7F6A54Fb28fA7fb5d46a6ed08cC5E;
    address constant LUX_LPOPCAT = 0xc78eaf37e8C37c5E4e4A8DE24bcDa7FeDAe79f9C;
    address constant LUX_LPONKE = 0xDfDf9037DbC42a8EcD7d7eCd6f0FE94EB2F23aee;
    address constant LUX_LMEW = 0x4f96a2c12e4A1C87E16d8b5F9B1a7c6B8d32F4b7;
    address constant LUX_LDOGS = 0x47D0F65cb88E1F7B888b18D83CC2c5F77BF4C36c;
    address constant LUX_LFWOG = 0x6F52A8adF0E8E20C20A8F7fB2B8cDDE9b6E8E6F8;
    address constant LUX_LGIGA = 0x2b3F5c2b8E6C5E2D8E8F5C2B8E6C5E2D8E8F5C2B;
    address constant LUX_LMOODENG = 0x8f3A5b7c8D9E2F1A3B5C7D9E2F1A3B5C7D9E2F1A;
    address constant LUX_LPNUT = 0x1c5F7e8A9B2C3D4E5F6A7B8C9D0E1F2A3B4C5D6E;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // Zoo Mainnet (200200) - Bridge Tokens
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Native wrapped ZOO
    address constant ZOO_WZOO = 0x4888E4a2Ee0F03051c72D2BD3ACf755eD3498B3E;
    
    // Stablecoins (teleport-minted from other chains)
    address constant ZOO_ZUSD = 0x848Cff46eb323f323b6Bbe1Df274E40793d7f2c2;  // Zoo USD
    
    // Major cryptos (teleport-minted from other chains)
    address constant ZOO_ZBTC = 0x1E48D32a4F5e9f08DB9aE4959163300FaF8A6C8e;  // Zoo BTC
    address constant ZOO_ZETH = 0x60E0a8167FC13dE89348978860466C9ceC24B9ba;  // Zoo ETH
    address constant ZOO_ZBNB = 0x6EdcF3645DeF09DB45050638c41157D8B9FEa1cf;  // Zoo BNB
    address constant ZOO_ZPOL = 0x28BfC5DD4B7E15659e41190983e5fE3df1132bB9;  // Zoo POL
    address constant ZOO_ZCELO = 0x3078847F879A33994cDa2Ec1540ca52b5E0eE2e5; // Zoo CELO
    address constant ZOO_ZFTM = 0x8B982132d639527E8a0eAAD385f97719af8f5e04;  // Zoo FTM
    address constant ZOO_ZXDAI = 0x7dfb3cBf7CF9c96fd56e3601FBA50AF45C731211; // Zoo xDAI
    address constant ZOO_ZSOL = 0x26B40f650156C7EbF9e087Dd0dca181Fe87625B7;  // Zoo SOL
    address constant ZOO_ZTON = 0x3141b94b89691009b950c96e97Bff48e0C543E3C;  // Zoo TON
    address constant ZOO_ZAVAX = 0x0e4bD0DD67c15dECfBBBdbbE07FC9d51D737693D; // Zoo AVAX
    address constant ZOO_ZBLAST = 0x94f49D0F4C62bbE4238F4AaA9200287bea9F2976; // Zoo BLAST
    
    // Cross-chain tokens
    address constant ZOO_ZLUX = 0x5E5290f350352768bD2bfC59c2DA15DD04A7cB88;  // Zoo LUX
    
    // Zoo-native meme tokens
    address constant ZOO_TRUMP = 0x7a58c0Be72BE218B41C608B7Fe7C5bB630736C71;
    address constant ZOO_MELANIA = 0x85c1234567890AbCdEf1234567890AbCdEf123456;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // Uniswap V2/V3 Addresses (Same on Lux & Zoo)
    // ═══════════════════════════════════════════════════════════════════════════
    
    address constant V2_FACTORY = 0xD173926A10A0C4eCd3A51B1422270b65Df0551c1;
    address constant V2_ROUTER = 0xAe2cf1E403aAFE6C05A5b8Ef63EB19ba591d8511;
    address constant V3_FACTORY = 0x80bBc7C4C7a59C899D1B37BC14539A22D5830a84;
    address constant SWAP_ROUTER = 0x939bC0Bca6F9B9c52E6e3AD8A3C590b5d9B9D10E;
    address constant MULTICALL = 0xd25F88CBdAe3c2CCA3Bb75FC4E723b44C0Ea362F;
    address constant NFT_POSITION_MANAGER = 0x82DE420f04a3F9Ab5fB46B21C0eb02d49e75BcE2;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // Helper Functions
    // ═══════════════════════════════════════════════════════════════════════════
    
    function getWrappedNative(uint256 chainId) internal pure returns (address) {
        if (chainId == LUX_MAINNET || chainId == LUX_TESTNET) {
            return LUX_WLUX;
        } else if (chainId == ZOO_MAINNET) {
            return ZOO_WZOO;
        }
        revert("Unsupported chain");
    }
    
    function getStablecoin(uint256 chainId) internal pure returns (address) {
        if (chainId == LUX_MAINNET || chainId == LUX_TESTNET) {
            return LUX_LUSD;
        } else if (chainId == ZOO_MAINNET) {
            return ZOO_ZUSD;
        }
        revert("Unsupported chain");
    }
    
    function getBTC(uint256 chainId) internal pure returns (address) {
        if (chainId == LUX_MAINNET || chainId == LUX_TESTNET) {
            return LUX_LBTC;
        } else if (chainId == ZOO_MAINNET) {
            return ZOO_ZBTC;
        }
        revert("Unsupported chain");
    }
    
    function getETH(uint256 chainId) internal pure returns (address) {
        if (chainId == LUX_MAINNET || chainId == LUX_TESTNET) {
            return LUX_LETH;
        } else if (chainId == ZOO_MAINNET) {
            return ZOO_ZETH;
        }
        revert("Unsupported chain");
    }
    
    function isLuxChain(uint256 chainId) internal pure returns (bool) {
        return chainId == LUX_MAINNET || chainId == LUX_TESTNET;
    }
    
    function isZooChain(uint256 chainId) internal pure returns (bool) {
        return chainId == ZOO_MAINNET;
    }
    
    function isHanzoChain(uint256 chainId) internal pure returns (bool) {
        return chainId == HANZO_MAINNET;
    }
}
