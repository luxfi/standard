import { DocsLayout } from 'fumadocs-ui/layouts/docs';
import { source } from '@/lib/source';
import type { ReactNode } from 'react';

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <DocsLayout
      tree={source.pageTree}
      nav={{
        title: 'Lux Standard',
      }}
      links={[
        {
          text: 'Precompiles',
          url: 'https://precompile.lux.network',
          external: true,
        },
      ]}
    >
      {children}
    </DocsLayout>
  );
}
