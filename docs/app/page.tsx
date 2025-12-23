import Link from 'next/link';

export default function Home() {
  return (
    <main className="min-h-screen flex flex-col items-center justify-center p-8">
      <div className="max-w-3xl text-center">
        <h1 className="text-5xl font-bold mb-6">
          Lux Standard Library
        </h1>
        <p className="text-xl text-fd-muted-foreground mb-8">
          Smart contract library for the Lux Network ecosystem.
          Tokens, DeFi, governance, and cross-chain protocols.
        </p>
        <Link
          href="/docs"
          className="inline-flex items-center justify-center rounded-md bg-fd-primary px-6 py-3 text-sm font-medium text-fd-primary-foreground transition-colors hover:bg-fd-primary/90"
        >
          View Documentation →
        </Link>
      </div>
    </main>
  );
}
