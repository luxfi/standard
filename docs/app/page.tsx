import Link from "next/link";

export default function Home() {
  return (
    <main className="min-h-screen bg-gradient-to-b from-gray-900 to-black text-white">
      <div className="max-w-6xl mx-auto px-4 py-16">
        <header className="text-center mb-16">
          <h1 className="text-5xl font-bold mb-4 bg-gradient-to-r from-blue-400 to-purple-500 bg-clip-text text-transparent">
            Lux Standard Library
          </h1>
          <p className="text-xl text-gray-400 max-w-2xl mx-auto">
            Comprehensive smart contract library for the Lux Network ecosystem.
            One canonical way to do everything - composable, orthogonal, secure.
          </p>
        </header>

        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
          {/* QuantumSwap DEX */}
          <div className="bg-gray-800 rounded-lg p-6 hover:bg-gray-700 transition-colors">
            <h2 className="text-xl font-semibold text-blue-400 mb-2">QuantumSwap DEX</h2>
            <p className="text-gray-400 text-sm mb-4">
              434M orders/sec, 2ns latency, full on-chain CLOB with post-quantum security.
            </p>
            <span className="text-xs bg-blue-900/50 text-blue-300 px-2 py-1 rounded">LP-2500</span>
          </div>

          {/* DeFi Protocols */}
          <div className="bg-gray-800 rounded-lg p-6 hover:bg-gray-700 transition-colors">
            <h2 className="text-xl font-semibold text-green-400 mb-2">DeFi Protocols</h2>
            <p className="text-gray-400 text-sm mb-4">
              Compound lending, Alchemix self-repaying loans, yield farming, and more.
            </p>
            <span className="text-xs bg-green-900/50 text-green-300 px-2 py-1 rounded">LP-2508-2509</span>
          </div>

          {/* NFT Marketplace */}
          <div className="bg-gray-800 rounded-lg p-6 hover:bg-gray-700 transition-colors">
            <h2 className="text-xl font-semibold text-purple-400 mb-2">NFT Marketplace</h2>
            <p className="text-gray-400 text-sm mb-4">
              Media registry with on-chain royalties and decentralized content metadata.
            </p>
            <span className="text-xs bg-purple-900/50 text-purple-300 px-2 py-1 rounded">LP-2502</span>
          </div>

          {/* Account Abstraction */}
          <div className="bg-gray-800 rounded-lg p-6 hover:bg-gray-700 transition-colors">
            <h2 className="text-xl font-semibold text-yellow-400 mb-2">Account Abstraction</h2>
            <p className="text-gray-400 text-sm mb-4">
              ERC-4337 smart accounts with session keys, paymasters, and bundlers.
            </p>
            <span className="text-xs bg-yellow-900/50 text-yellow-300 px-2 py-1 rounded">LP-2503</span>
          </div>

          {/* Safe Multisig */}
          <div className="bg-gray-800 rounded-lg p-6 hover:bg-gray-700 transition-colors">
            <h2 className="text-xl font-semibold text-red-400 mb-2">Safe Multisig</h2>
            <p className="text-gray-400 text-sm mb-4">
              Battle-tested multisig with modules, guards, and Lamport signatures.
            </p>
            <span className="text-xs bg-red-900/50 text-red-300 px-2 py-1 rounded">LP-2504</span>
          </div>

          {/* DAO Governance */}
          <div className="bg-gray-800 rounded-lg p-6 hover:bg-gray-700 transition-colors">
            <h2 className="text-xl font-semibold text-cyan-400 mb-2">DAO Governance</h2>
            <p className="text-gray-400 text-sm mb-4">
              OpenZeppelin Governor with timelocks, voting, and proposal management.
            </p>
            <span className="text-xs bg-cyan-900/50 text-cyan-300 px-2 py-1 rounded">LP-2505</span>
          </div>

          {/* Teleport Bridge */}
          <div className="bg-gray-800 rounded-lg p-6 hover:bg-gray-700 transition-colors">
            <h2 className="text-xl font-semibold text-orange-400 mb-2">Teleport Bridge</h2>
            <p className="text-gray-400 text-sm mb-4">
              MPC Bridge with 2-of-3 threshold signatures for 15+ EVM chains.
            </p>
            <span className="text-xs bg-orange-900/50 text-orange-300 px-2 py-1 rounded">LP-2507</span>
          </div>

          {/* Precompiles */}
          <div className="bg-gray-800 rounded-lg p-6 hover:bg-gray-700 transition-colors">
            <h2 className="text-xl font-semibold text-pink-400 mb-2">Precompiles</h2>
            <p className="text-gray-400 text-sm mb-4">
              FROST, CGGMP21, Ringtail, ML-DSA, Warp, Quasar threshold signatures.
            </p>
            <span className="text-xs bg-pink-900/50 text-pink-300 px-2 py-1 rounded">LP-2511-2517</span>
          </div>

          {/* AI Confidential Compute */}
          <div className="bg-gray-800 rounded-lg p-6 hover:bg-gray-700 transition-colors">
            <h2 className="text-xl font-semibold text-indigo-400 mb-2">AI Confidential Compute</h2>
            <p className="text-gray-400 text-sm mb-4">
              3-tier CC system: GPU-native, Confidential VM, Device TEE for AI mining.
            </p>
            <span className="text-xs bg-indigo-900/50 text-indigo-300 px-2 py-1 rounded">LP-5610</span>
          </div>
        </div>

        <div className="mt-16 text-center">
          <h3 className="text-2xl font-semibold mb-4">Build Status</h3>
          <div className="flex justify-center gap-4">
            <img
              src="https://github.com/luxfi/standard/actions/workflows/ci.yml/badge.svg"
              alt="CI Status"
              className="rounded"
            />
            <img
              src="https://github.com/luxfi/standard/actions/workflows/deploy.yml/badge.svg"
              alt="Deploy Status"
              className="rounded"
            />
          </div>
        </div>

        <footer className="mt-16 pt-8 border-t border-gray-800 text-center text-gray-500">
          <p>© 2025 Lux Industries. MIT Licensed.</p>
          <div className="mt-4 flex justify-center gap-6">
            <a href="https://github.com/luxfi/standard" className="hover:text-white transition-colors">GitHub</a>
            <a href="https://lux.network" className="hover:text-white transition-colors">Lux Network</a>
            <a href="https://lps.lux.network" className="hover:text-white transition-colors">LPs</a>
          </div>
        </footer>
      </div>
    </main>
  );
}
