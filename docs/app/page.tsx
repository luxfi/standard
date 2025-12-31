import Link from 'next/link';

const features = [
  {
    title: 'Tokens',
    description: 'LUX, LUXD stablecoin, AI token, bridgeable ERC20/ERC721',
    href: '/docs/tokens',
    icon: '🪙',
  },
  {
    title: 'DeFi',
    description: 'Self-repaying loans, perpetuals, lending, yield farming',
    href: '/docs/defi',
    icon: '📈',
  },
  {
    title: 'AMM',
    description: 'Uniswap V2/V3 pools, QuantumSwap router, WLUX',
    href: '/docs/amm',
    icon: '🔄',
  },
  {
    title: 'Smart Accounts',
    description: 'ERC-4337 abstraction, session keys, paymasters',
    href: '/docs/accounts',
    icon: '👤',
  },
  {
    title: 'Governance',
    description: 'DAO, voting, timelocks, veLUX tokenomics',
    href: '/docs/governance',
    icon: '🏛️',
  },
  {
    title: 'Bridge',
    description: 'Cross-chain with Warp messaging and MPC validation',
    href: '/docs/bridge',
    icon: '🌉',
  },
  {
    title: 'Safe',
    description: 'Multi-sig wallets, FROST threshold signatures',
    href: '/docs/safe',
    icon: '🔐',
  },
  {
    title: 'Post-Quantum',
    description: 'Lamport signatures, ML-DSA, quantum-safe crypto',
    href: '/docs/lamport',
    icon: '⚛️',
  },
];

const stats = [
  { label: 'Contracts', value: '469' },
  { label: 'Tests', value: '751' },
  { label: 'Coverage', value: '95%' },
  { label: 'Audits', value: '3' },
];

export default function Home() {
  return (
    <main className="min-h-screen">
      {/* Hero Section */}
      <section className="relative overflow-hidden bg-gradient-to-b from-fd-background to-fd-muted/30">
        <div className="absolute inset-0 bg-grid-white/[0.02] bg-[size:60px_60px]" />
        <div className="relative mx-auto max-w-7xl px-6 py-24 sm:py-32 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <div className="mb-8 flex justify-center">
              <div className="rounded-full bg-fd-primary/10 px-4 py-1.5 text-sm font-medium text-fd-primary ring-1 ring-inset ring-fd-primary/20">
                v1.0.0 — Production Ready
              </div>
            </div>
            <h1 className="text-4xl font-bold tracking-tight sm:text-6xl bg-gradient-to-r from-fd-foreground to-fd-foreground/70 bg-clip-text text-transparent">
              Lux Standard Library
            </h1>
            <p className="mt-6 text-lg leading-8 text-fd-muted-foreground">
              The canonical smart contract library for Lux Network.
              Battle-tested implementations for tokens, DeFi, governance,
              and post-quantum security.
            </p>
            <div className="mt-10 flex items-center justify-center gap-x-4">
              <Link
                href="/docs"
                className="rounded-lg bg-fd-primary px-5 py-2.5 text-sm font-semibold text-fd-primary-foreground shadow-sm hover:bg-fd-primary/90 transition-colors"
              >
                Get Started
              </Link>
              <Link
                href="https://github.com/luxfi/standard"
                className="rounded-lg px-5 py-2.5 text-sm font-semibold text-fd-foreground ring-1 ring-fd-border hover:bg-fd-muted transition-colors"
              >
                GitHub →
              </Link>
            </div>
          </div>
        </div>
      </section>

      {/* Stats Section */}
      <section className="border-y border-fd-border bg-fd-muted/30">
        <div className="mx-auto max-w-7xl px-6 py-12 lg:px-8">
          <dl className="grid grid-cols-2 gap-x-8 gap-y-8 text-center lg:grid-cols-4">
            {stats.map((stat) => (
              <div key={stat.label} className="mx-auto flex max-w-xs flex-col">
                <dt className="text-base leading-7 text-fd-muted-foreground">{stat.label}</dt>
                <dd className="order-first text-3xl font-semibold tracking-tight text-fd-foreground">{stat.value}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>

      {/* Features Grid */}
      <section className="mx-auto max-w-7xl px-6 py-24 lg:px-8">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
            Everything you need to build on Lux
          </h2>
          <p className="mt-4 text-lg text-fd-muted-foreground">
            Composable, audited contracts following best practices
          </p>
        </div>
        <div className="mx-auto mt-16 grid max-w-5xl grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {features.map((feature) => (
            <Link
              key={feature.title}
              href={feature.href}
              className="group relative rounded-xl border border-fd-border bg-fd-card p-6 hover:border-fd-primary/50 hover:bg-fd-muted/50 transition-all"
            >
              <div className="text-3xl mb-4">{feature.icon}</div>
              <h3 className="text-lg font-semibold text-fd-foreground group-hover:text-fd-primary transition-colors">
                {feature.title}
              </h3>
              <p className="mt-2 text-sm text-fd-muted-foreground">
                {feature.description}
              </p>
            </Link>
          ))}
        </div>
      </section>

      {/* Quick Start Section */}
      <section className="border-t border-fd-border bg-fd-muted/30">
        <div className="mx-auto max-w-7xl px-6 py-24 lg:px-8">
          <div className="mx-auto max-w-2xl">
            <h2 className="text-2xl font-bold tracking-tight mb-8">Quick Start</h2>
            <div className="rounded-xl border border-fd-border bg-fd-card overflow-hidden">
              <div className="border-b border-fd-border px-4 py-2 bg-fd-muted/50">
                <span className="text-sm text-fd-muted-foreground">Terminal</span>
              </div>
              <pre className="p-4 text-sm overflow-x-auto">
                <code className="text-fd-foreground">{`# Install with Foundry
forge install luxfi/standard

# Add to remappings.txt
@lux/=lib/standard/contracts/

# Import in your contract
import "@lux/tokens/LUX.sol";
import "@lux/defi/liquid/LiquidLUX.sol";`}</code>
              </pre>
            </div>
            <div className="mt-8 flex gap-4">
              <Link
                href="/docs/getting-started"
                className="text-sm font-medium text-fd-primary hover:text-fd-primary/80"
              >
                Read the full guide →
              </Link>
              <Link
                href="/docs/examples"
                className="text-sm font-medium text-fd-muted-foreground hover:text-fd-foreground"
              >
                View examples
              </Link>
            </div>
          </div>
        </div>
      </section>

      {/* Architecture Section */}
      <section className="mx-auto max-w-7xl px-6 py-24 lg:px-8">
        <div className="mx-auto max-w-2xl text-center mb-16">
          <h2 className="text-3xl font-bold tracking-tight">Design Principles</h2>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8 max-w-5xl mx-auto">
          <div className="text-center">
            <div className="mx-auto w-12 h-12 rounded-full bg-fd-primary/10 flex items-center justify-center mb-4">
              <span className="text-2xl">🧩</span>
            </div>
            <h3 className="font-semibold mb-2">Composable</h3>
            <p className="text-sm text-fd-muted-foreground">
              Contracts work together seamlessly. Mix and match protocols to build complex systems.
            </p>
          </div>
          <div className="text-center">
            <div className="mx-auto w-12 h-12 rounded-full bg-fd-primary/10 flex items-center justify-center mb-4">
              <span className="text-2xl">🎯</span>
            </div>
            <h3 className="font-semibold mb-2">Orthogonal</h3>
            <p className="text-sm text-fd-muted-foreground">
              Each contract does one thing well. Clean separation of concerns throughout.
            </p>
          </div>
          <div className="text-center">
            <div className="mx-auto w-12 h-12 rounded-full bg-fd-primary/10 flex items-center justify-center mb-4">
              <span className="text-2xl">🔒</span>
            </div>
            <h3 className="font-semibold mb-2">Secure</h3>
            <p className="text-sm text-fd-muted-foreground">
              Audited implementations with post-quantum cryptography support.
            </p>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-fd-border">
        <div className="mx-auto max-w-7xl px-6 py-12 lg:px-8">
          <div className="flex flex-col items-center justify-between gap-4 sm:flex-row">
            <p className="text-sm text-fd-muted-foreground">
              © 2025 Lux Industries. MIT License.
            </p>
            <div className="flex gap-6">
              <Link href="https://github.com/luxfi/standard" className="text-sm text-fd-muted-foreground hover:text-fd-foreground">
                GitHub
              </Link>
              <Link href="https://discord.gg/lux" className="text-sm text-fd-muted-foreground hover:text-fd-foreground">
                Discord
              </Link>
              <Link href="https://twitter.com/luxnetwork" className="text-sm text-fd-muted-foreground hover:text-fd-foreground">
                Twitter
              </Link>
            </div>
          </div>
        </div>
      </footer>
    </main>
  );
}
