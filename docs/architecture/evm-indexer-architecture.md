# Lux EVM Indexer Architecture

**Version**: 1.0.0
**Status**: DESIGN PROPOSAL
**Date**: 2025-12-25
**Author**: Architecture Team

---

## Executive Summary

This document outlines the architecture for **Lux Indexer**, a high-performance, Go-based EVM blockchain indexer designed to replace Blockscout while maintaining full API compatibility. The indexer is optimized for the Lux ecosystem (C-Chain 96369, Zoo 200200, Hanzo 36963) with support for horizontal scaling to millions of blocks.

### Key Design Goals

1. **High Performance**: Index 10,000+ blocks/second, handle 50K+ API requests/second
2. **Horizontal Scalability**: Shard by chain/block range, stateless API workers
3. **Real-time Updates**: Sub-second block notifications via WebSocket/SSE
4. **API Compatibility**: Full Etherscan API + Blockscout API + GraphQL
5. **Native Lux Support**: Multi-chain, Warp messaging, precompile awareness
6. **Operational Excellence**: Zero-downtime upgrades, comprehensive observability

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Core Module Structure](#2-core-module-structure)
3. [Database Schema](#3-database-schema)
4. [Indexer Pipeline](#4-indexer-pipeline)
5. [API Layer](#5-api-layer)
6. [Real-time Subscriptions](#6-real-time-subscriptions)
7. [Contract Verification](#7-contract-verification)
8. [Deployment Architecture](#8-deployment-architecture)
9. [Performance Benchmarks](#9-performance-benchmarks)
10. [Migration Strategy](#10-migration-strategy)

---

## 1. System Overview

### High-Level Architecture

```
                                    ┌─────────────────────────────────────────────────────────────────┐
                                    │                     LOAD BALANCER                                │
                                    │                   (HAProxy/Nginx)                                │
                                    └───────────────────────────┬─────────────────────────────────────┘
                                                                │
                    ┌───────────────────────────────────────────┼───────────────────────────────────────────┐
                    │                                           │                                           │
                    ▼                                           ▼                                           ▼
┌───────────────────────────────────────┐  ┌───────────────────────────────────────┐  ┌───────────────────────────────────────┐
│           API WORKER POOL             │  │           API WORKER POOL             │  │           API WORKER POOL             │
│  ┌─────────────────────────────────┐  │  │  ┌─────────────────────────────────┐  │  │  ┌─────────────────────────────────┐  │
│  │     REST API (Etherscan)        │  │  │  │     REST API (Etherscan)        │  │  │  │     REST API (Etherscan)        │  │
│  │     REST API (Blockscout)       │  │  │  │     REST API (Blockscout)       │  │  │  │     REST API (Blockscout)       │  │
│  │     GraphQL Endpoint            │  │  │  │     GraphQL Endpoint            │  │  │  │     GraphQL Endpoint            │  │
│  │     WebSocket Server            │  │  │  │     WebSocket Server            │  │  │  │     WebSocket Server            │  │
│  └─────────────────────────────────┘  │  │  └─────────────────────────────────┘  │  │  └─────────────────────────────────┘  │
└───────────────────────────────────────┘  └───────────────────────────────────────┘  └───────────────────────────────────────┘
                    │                                           │                                           │
                    └───────────────────────────────────────────┼───────────────────────────────────────────┘
                                                                │
                                    ┌───────────────────────────┴───────────────────────────┐
                                    │                                                       │
                                    ▼                                                       ▼
                    ┌───────────────────────────────────┐               ┌───────────────────────────────────┐
                    │           REDIS CLUSTER           │               │         PostgreSQL CLUSTER        │
                    │  ┌─────────────────────────────┐  │               │  ┌─────────────────────────────┐  │
                    │  │ Cache (blocks, txs, accts)  │  │               │  │   Primary (write)           │  │
                    │  │ Pub/Sub (real-time events)  │  │               │  │   Read Replicas (N)         │  │
                    │  │ Rate Limiting               │  │               │  │   Sharded by chain_id       │  │
                    │  │ Session Storage             │  │               │  └─────────────────────────────┘  │
                    │  └─────────────────────────────┘  │               └───────────────────────────────────┘
                    └───────────────────────────────────┘                               ▲
                                                                                        │
                    ┌───────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                              INDEXER PIPELINE                                                                  │
│                                                                                                                               │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐             │
│  │  Block Fetcher  │───▶│  TX Processor   │───▶│  Log Decoder    │───▶│ Token Tracker   │───▶│  DB Writer      │             │
│  │  (parallel)     │    │  (receipts)     │    │  (ABI decode)   │    │  (ERC20/721)    │    │  (batch insert) │             │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘             │
│           │                     │                      │                      │                      │                        │
│           │                     │                      │                      │                      │                        │
│           ▼                     ▼                      ▼                      ▼                      ▼                        │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐ │
│  │                                        PIPELINE COORDINATOR                                                              │ │
│  │    • Block range assignment    • Checkpoint management    • Reorg detection    • Gap filling    • Health monitoring    │ │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                              EVM NODES (RPC Sources)                                                           │
│                                                                                                                               │
│  ┌─────────────────────────┐    ┌─────────────────────────┐    ┌─────────────────────────┐    ┌─────────────────────────┐   │
│  │   C-Chain (96369)       │    │   Zoo (200200)          │    │   Hanzo (36963)         │    │   Other Subnets         │   │
│  │   Primary + Backup      │    │   Primary + Backup      │    │   Primary + Backup      │    │   Primary + Backup      │   │
│  └─────────────────────────┘    └─────────────────────────┘    └─────────────────────────┘    └─────────────────────────┘   │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Component Summary

| Component | Technology | Purpose | Scaling Strategy |
|-----------|------------|---------|------------------|
| API Workers | Go + Chi/Gin | REST/GraphQL/WS endpoints | Horizontal (stateless) |
| Indexer Pipeline | Go + goroutines | Block/TX processing | Vertical + Range sharding |
| PostgreSQL | PostgreSQL 16 | Persistent storage | Read replicas + Citus sharding |
| Redis | Redis 7 Cluster | Caching + Pub/Sub | Cluster mode |
| Message Queue | NATS JetStream | Event distribution | Stream replication |

---

## 2. Core Module Structure

### Go Module Layout

```
github.com/luxfi/indexer/
├── cmd/
│   ├── indexer/              # Main indexer binary
│   │   └── main.go
│   ├── api/                  # API server binary
│   │   └── main.go
│   ├── worker/               # Background worker binary
│   │   └── main.go
│   └── migrate/              # Database migration tool
│       └── main.go
│
├── internal/
│   ├── config/               # Configuration management
│   │   ├── config.go         # Config struct definitions
│   │   ├── loader.go         # ENV/file/flag loading
│   │   └── validate.go       # Config validation
│   │
│   ├── chain/                # Chain abstraction layer
│   │   ├── client.go         # RPC client pool
│   │   ├── types.go          # Chain-specific types
│   │   ├── lux/              # Lux C-chain specifics
│   │   │   ├── header.go     # 19-field header handling
│   │   │   └── warp.go       # Warp message decoding
│   │   └── eth/              # Standard Ethereum
│   │       └── client.go
│   │
│   ├── indexer/              # Indexing pipeline
│   │   ├── coordinator.go    # Pipeline orchestration
│   │   ├── fetcher.go        # Block fetching
│   │   ├── processor.go      # TX/receipt processing
│   │   ├── decoder.go        # Log/event decoding
│   │   ├── tracker.go        # Token tracking (ERC20/721/1155)
│   │   ├── writer.go         # Batch DB writes
│   │   ├── reorg.go          # Reorg detection/handling
│   │   └── checkpoint.go     # Progress checkpointing
│   │
│   ├── api/                  # API layer
│   │   ├── server.go         # HTTP server setup
│   │   ├── middleware/       # Auth, rate limiting, CORS
│   │   │   ├── ratelimit.go
│   │   │   ├── auth.go
│   │   │   └── cors.go
│   │   ├── rest/             # REST handlers
│   │   │   ├── etherscan/    # Etherscan API compatibility
│   │   │   │   ├── account.go
│   │   │   │   ├── contract.go
│   │   │   │   ├── transaction.go
│   │   │   │   ├── block.go
│   │   │   │   ├── logs.go
│   │   │   │   ├── token.go
│   │   │   │   └── stats.go
│   │   │   └── blockscout/   # Blockscout API compatibility
│   │   │       ├── addresses.go
│   │   │       ├── blocks.go
│   │   │       ├── transactions.go
│   │   │       ├── tokens.go
│   │   │       ├── smart_contracts.go
│   │   │       └── stats.go
│   │   ├── graphql/          # GraphQL resolvers
│   │   │   ├── schema.go
│   │   │   ├── resolvers.go
│   │   │   ├── types.go
│   │   │   └── loaders.go    # DataLoader for N+1 prevention
│   │   └── ws/               # WebSocket handlers
│   │       ├── hub.go        # Connection management
│   │       ├── subscription.go
│   │       └── broadcast.go
│   │
│   ├── storage/              # Data access layer
│   │   ├── postgres/         # PostgreSQL implementation
│   │   │   ├── db.go         # Connection pool
│   │   │   ├── blocks.go     # Block queries
│   │   │   ├── transactions.go
│   │   │   ├── logs.go
│   │   │   ├── tokens.go
│   │   │   ├── contracts.go
│   │   │   ├── addresses.go
│   │   │   └── stats.go
│   │   ├── redis/            # Redis caching
│   │   │   ├── cache.go
│   │   │   ├── pubsub.go
│   │   │   └── ratelimit.go
│   │   └── interfaces.go     # Storage interfaces
│   │
│   ├── verify/               # Contract verification
│   │   ├── solidity.go       # Solidity compiler integration
│   │   ├── vyper.go          # Vyper support
│   │   ├── sourcify.go       # Sourcify integration
│   │   ├── etherscan.go      # Etherscan import
│   │   └── storage.go        # Verified source storage
│   │
│   ├── decode/               # ABI decoding
│   │   ├── abi.go            # ABI parser/decoder
│   │   ├── signature.go      # 4-byte signature database
│   │   ├── erc20.go          # ERC-20 event decoder
│   │   ├── erc721.go         # ERC-721 event decoder
│   │   ├── erc1155.go        # ERC-1155 event decoder
│   │   └── precompiles.go    # Lux precompile decoding
│   │
│   └── metrics/              # Observability
│       ├── prometheus.go     # Prometheus metrics
│       ├── tracing.go        # OpenTelemetry tracing
│       └── logging.go        # Structured logging
│
├── pkg/                      # Public packages
│   ├── types/                # Shared types
│   │   ├── block.go
│   │   ├── transaction.go
│   │   ├── log.go
│   │   ├── token.go
│   │   └── address.go
│   ├── client/               # Client SDK
│   │   ├── client.go
│   │   └── options.go
│   └── testutil/             # Test utilities
│       ├── fixtures.go
│       └── mock.go
│
├── migrations/               # Database migrations
│   ├── 001_initial_schema.sql
│   ├── 002_indexes.sql
│   ├── 003_partitioning.sql
│   └── ...
│
├── api/                      # API specifications
│   ├── openapi.yaml          # OpenAPI 3.0 spec
│   └── graphql/
│       └── schema.graphql
│
├── scripts/                  # Operational scripts
│   ├── deploy.sh
│   ├── backup.sh
│   └── benchmark.sh
│
├── docker/
│   ├── Dockerfile.indexer
│   ├── Dockerfile.api
│   └── compose.yml
│
├── go.mod
├── go.sum
├── Makefile
└── README.md
```

### Key Interfaces

```go
// internal/storage/interfaces.go

package storage

import (
    "context"
    "github.com/luxfi/indexer/pkg/types"
)

// BlockStore handles block persistence and retrieval
type BlockStore interface {
    // Write operations
    InsertBlock(ctx context.Context, block *types.Block) error
    InsertBlocks(ctx context.Context, blocks []*types.Block) error
    DeleteBlock(ctx context.Context, number uint64) error

    // Read operations
    GetBlockByNumber(ctx context.Context, number uint64) (*types.Block, error)
    GetBlockByHash(ctx context.Context, hash string) (*types.Block, error)
    GetBlockRange(ctx context.Context, start, end uint64) ([]*types.Block, error)
    GetLatestBlock(ctx context.Context) (*types.Block, error)

    // Stats
    GetBlockCount(ctx context.Context) (uint64, error)
    GetAverageBlockTime(ctx context.Context, window int) (float64, error)
}

// TransactionStore handles transaction persistence
type TransactionStore interface {
    InsertTransaction(ctx context.Context, tx *types.Transaction) error
    InsertTransactions(ctx context.Context, txs []*types.Transaction) error

    GetTransactionByHash(ctx context.Context, hash string) (*types.Transaction, error)
    GetTransactionsByBlock(ctx context.Context, blockNumber uint64) ([]*types.Transaction, error)
    GetTransactionsByAddress(ctx context.Context, address string, opts *QueryOptions) ([]*types.Transaction, error)
    GetInternalTransactions(ctx context.Context, txHash string) ([]*types.InternalTransaction, error)
}

// LogStore handles event log persistence
type LogStore interface {
    InsertLogs(ctx context.Context, logs []*types.Log) error

    GetLogsByFilter(ctx context.Context, filter *types.LogFilter) ([]*types.Log, error)
    GetLogsByTransaction(ctx context.Context, txHash string) ([]*types.Log, error)
    GetLogsByAddress(ctx context.Context, address string, opts *QueryOptions) ([]*types.Log, error)
    GetLogsByTopic(ctx context.Context, topic string, opts *QueryOptions) ([]*types.Log, error)
}

// TokenStore handles token metadata and transfers
type TokenStore interface {
    UpsertToken(ctx context.Context, token *types.Token) error
    GetToken(ctx context.Context, address string) (*types.Token, error)
    GetTokenHolders(ctx context.Context, address string, opts *QueryOptions) ([]*types.TokenHolder, error)
    GetTokenTransfers(ctx context.Context, address string, opts *QueryOptions) ([]*types.TokenTransfer, error)
    GetAddressTokens(ctx context.Context, address string) ([]*types.TokenBalance, error)
}

// ContractStore handles verified contracts
type ContractStore interface {
    InsertContract(ctx context.Context, contract *types.Contract) error
    GetContract(ctx context.Context, address string) (*types.Contract, error)
    UpdateVerification(ctx context.Context, address string, verification *types.Verification) error
    SearchContracts(ctx context.Context, query string, opts *QueryOptions) ([]*types.Contract, error)
}

// AddressStore handles address metadata
type AddressStore interface {
    UpsertAddress(ctx context.Context, address *types.Address) error
    GetAddress(ctx context.Context, address string) (*types.Address, error)
    GetTopAddresses(ctx context.Context, by string, limit int) ([]*types.Address, error)
    UpdateBalance(ctx context.Context, address string, balance string) error
}

// QueryOptions for pagination and filtering
type QueryOptions struct {
    Offset      int
    Limit       int
    StartBlock  *uint64
    EndBlock    *uint64
    StartTime   *int64
    EndTime     *int64
    Sort        string // "asc" or "desc"
    SortBy      string
}
```

---

## 3. Database Schema

### PostgreSQL Schema Design

```sql
-- migrations/001_initial_schema.sql

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "pg_trgm";      -- Trigram for fuzzy search
CREATE EXTENSION IF NOT EXISTS "btree_gist";    -- GiST indexes
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements"; -- Query analysis

-- Chain configuration (multi-chain support)
CREATE TABLE chains (
    chain_id        BIGINT PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    symbol          VARCHAR(20) NOT NULL,
    decimals        INTEGER DEFAULT 18,
    rpc_url         TEXT NOT NULL,
    ws_url          TEXT,
    explorer_url    TEXT,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Insert Lux chains
INSERT INTO chains (chain_id, name, symbol, rpc_url) VALUES
    (96369, 'Lux C-Chain', 'LUX', 'http://localhost:9650/ext/bc/C/rpc'),
    (200200, 'Zoo Network', 'ZOO', 'http://localhost:9650/ext/bc/Zoo/rpc'),
    (36963, 'Hanzo AI', 'HANZO', 'http://localhost:9650/ext/bc/Hanzo/rpc');

-- Blocks table (partitioned by chain_id and block range)
CREATE TABLE blocks (
    id              BIGSERIAL,
    chain_id        BIGINT NOT NULL REFERENCES chains(chain_id),
    number          BIGINT NOT NULL,
    hash            BYTEA NOT NULL,
    parent_hash     BYTEA NOT NULL,
    nonce           BYTEA,
    miner           BYTEA NOT NULL,
    difficulty      NUMERIC(78),
    total_difficulty NUMERIC(78),
    size            INTEGER NOT NULL,
    gas_limit       BIGINT NOT NULL,
    gas_used        BIGINT NOT NULL,
    base_fee        NUMERIC(78),
    timestamp       BIGINT NOT NULL,
    transaction_count INTEGER NOT NULL DEFAULT 0,
    uncle_count     INTEGER NOT NULL DEFAULT 0,

    -- Lux-specific fields
    ext_data_hash   BYTEA,
    ext_data_gas_used BIGINT,
    block_gas_cost  NUMERIC(78),

    -- Ethereum 2.0 fields
    blob_gas_used   BIGINT,
    excess_blob_gas BIGINT,

    -- Metadata
    extra_data      BYTEA,
    logs_bloom      BYTEA,
    state_root      BYTEA,
    transactions_root BYTEA,
    receipts_root   BYTEA,
    sha3_uncles     BYTEA,

    -- Indexing metadata
    indexed_at      TIMESTAMPTZ DEFAULT NOW(),

    PRIMARY KEY (chain_id, number)
) PARTITION BY LIST (chain_id);

-- Create partitions for each chain
CREATE TABLE blocks_96369 PARTITION OF blocks FOR VALUES IN (96369);
CREATE TABLE blocks_200200 PARTITION OF blocks FOR VALUES IN (200200);
CREATE TABLE blocks_36963 PARTITION OF blocks FOR VALUES IN (36963);

-- Transactions table
CREATE TABLE transactions (
    id              BIGSERIAL,
    chain_id        BIGINT NOT NULL,
    hash            BYTEA NOT NULL,
    block_number    BIGINT NOT NULL,
    block_hash      BYTEA NOT NULL,
    transaction_index INTEGER NOT NULL,

    -- Core fields
    from_address    BYTEA NOT NULL,
    to_address      BYTEA,  -- NULL for contract creation
    value           NUMERIC(78) NOT NULL,
    gas             BIGINT NOT NULL,
    gas_price       NUMERIC(78),
    gas_used        BIGINT,

    -- EIP-1559 fields
    max_fee_per_gas NUMERIC(78),
    max_priority_fee NUMERIC(78),
    effective_gas_price NUMERIC(78),

    -- EIP-4844 blob fields
    max_fee_per_blob_gas NUMERIC(78),
    blob_gas_used   BIGINT,
    blob_gas_price  NUMERIC(78),
    blob_hashes     BYTEA[],

    -- TX data
    input           BYTEA,
    nonce           BIGINT NOT NULL,
    type            SMALLINT NOT NULL DEFAULT 0,

    -- Status
    status          SMALLINT,  -- 0 = failed, 1 = success
    error           TEXT,
    revert_reason   TEXT,

    -- Contract creation
    created_contract BYTEA,

    -- Signature
    v               BYTEA,
    r               BYTEA,
    s               BYTEA,

    -- Timestamps
    timestamp       BIGINT NOT NULL,
    indexed_at      TIMESTAMPTZ DEFAULT NOW(),

    PRIMARY KEY (chain_id, hash),
    FOREIGN KEY (chain_id, block_number) REFERENCES blocks(chain_id, number)
) PARTITION BY LIST (chain_id);

CREATE TABLE transactions_96369 PARTITION OF transactions FOR VALUES IN (96369);
CREATE TABLE transactions_200200 PARTITION OF transactions FOR VALUES IN (200200);
CREATE TABLE transactions_36963 PARTITION OF transactions FOR VALUES IN (36963);

-- Internal transactions (traces)
CREATE TABLE internal_transactions (
    id              BIGSERIAL,
    chain_id        BIGINT NOT NULL,
    transaction_hash BYTEA NOT NULL,
    block_number    BIGINT NOT NULL,
    trace_address   INTEGER[] NOT NULL,

    -- Trace data
    type            VARCHAR(20) NOT NULL,  -- call, create, suicide, reward
    call_type       VARCHAR(20),           -- call, delegatecall, staticcall
    from_address    BYTEA NOT NULL,
    to_address      BYTEA,
    value           NUMERIC(78) NOT NULL,
    gas             BIGINT,
    gas_used        BIGINT,
    input           BYTEA,
    output          BYTEA,
    error           TEXT,

    -- Created contract
    created_contract BYTEA,

    -- Indexing
    indexed_at      TIMESTAMPTZ DEFAULT NOW(),

    PRIMARY KEY (chain_id, transaction_hash, trace_address)
) PARTITION BY LIST (chain_id);

CREATE TABLE internal_transactions_96369 PARTITION OF internal_transactions FOR VALUES IN (96369);
CREATE TABLE internal_transactions_200200 PARTITION OF internal_transactions FOR VALUES IN (200200);
CREATE TABLE internal_transactions_36963 PARTITION OF internal_transactions FOR VALUES IN (36963);

-- Event logs
CREATE TABLE logs (
    id              BIGSERIAL,
    chain_id        BIGINT NOT NULL,
    block_number    BIGINT NOT NULL,
    block_hash      BYTEA NOT NULL,
    transaction_hash BYTEA NOT NULL,
    transaction_index INTEGER NOT NULL,
    log_index       INTEGER NOT NULL,

    -- Log data
    address         BYTEA NOT NULL,
    data            BYTEA,
    topic0          BYTEA,  -- Indexed separately for fast lookups
    topic1          BYTEA,
    topic2          BYTEA,
    topic3          BYTEA,
    topics          BYTEA[],  -- All topics as array

    -- Decoded data (if ABI available)
    decoded_name    VARCHAR(100),
    decoded_params  JSONB,

    -- Metadata
    removed         BOOLEAN DEFAULT FALSE,
    timestamp       BIGINT NOT NULL,
    indexed_at      TIMESTAMPTZ DEFAULT NOW(),

    PRIMARY KEY (chain_id, block_number, log_index)
) PARTITION BY LIST (chain_id);

CREATE TABLE logs_96369 PARTITION OF logs FOR VALUES IN (96369);
CREATE TABLE logs_200200 PARTITION OF logs FOR VALUES IN (200200);
CREATE TABLE logs_36963 PARTITION OF logs FOR VALUES IN (36963);

-- Addresses table
CREATE TABLE addresses (
    id              BIGSERIAL,
    chain_id        BIGINT NOT NULL,
    address         BYTEA NOT NULL,

    -- Balance (updated periodically)
    balance         NUMERIC(78) DEFAULT 0,
    balance_updated_at TIMESTAMPTZ,

    -- Contract info
    is_contract     BOOLEAN DEFAULT FALSE,
    bytecode        BYTEA,
    bytecode_hash   BYTEA,

    -- Verification
    is_verified     BOOLEAN DEFAULT FALSE,
    verification_id BIGINT,

    -- Stats
    transaction_count BIGINT DEFAULT 0,
    token_transfer_count BIGINT DEFAULT 0,

    -- Labels/tags
    name            VARCHAR(100),
    labels          TEXT[],

    -- Timestamps
    first_seen_block BIGINT,
    first_seen_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),

    PRIMARY KEY (chain_id, address)
) PARTITION BY LIST (chain_id);

CREATE TABLE addresses_96369 PARTITION OF addresses FOR VALUES IN (96369);
CREATE TABLE addresses_200200 PARTITION OF addresses FOR VALUES IN (200200);
CREATE TABLE addresses_36963 PARTITION OF addresses FOR VALUES IN (36963);

-- Smart contract verifications
CREATE TABLE contract_verifications (
    id              BIGSERIAL PRIMARY KEY,
    chain_id        BIGINT NOT NULL,
    address         BYTEA NOT NULL,

    -- Compiler info
    compiler_type   VARCHAR(20) NOT NULL,  -- solidity, vyper
    compiler_version VARCHAR(50) NOT NULL,
    optimization    BOOLEAN,
    optimization_runs INTEGER,
    evm_version     VARCHAR(20),

    -- Source
    contract_name   VARCHAR(100) NOT NULL,
    source_code     TEXT NOT NULL,
    abi             JSONB NOT NULL,
    constructor_args BYTEA,

    -- Multi-file
    is_multi_file   BOOLEAN DEFAULT FALSE,
    source_files    JSONB,  -- {filename: content}

    -- Verification metadata
    verified_at     TIMESTAMPTZ DEFAULT NOW(),
    verified_by     VARCHAR(100),  -- manual, sourcify, etherscan

    -- License
    license         VARCHAR(50),

    UNIQUE (chain_id, address)
);

-- Tokens (ERC-20, ERC-721, ERC-1155)
CREATE TABLE tokens (
    id              BIGSERIAL PRIMARY KEY,
    chain_id        BIGINT NOT NULL,
    address         BYTEA NOT NULL,

    -- Token info
    type            VARCHAR(20) NOT NULL,  -- ERC-20, ERC-721, ERC-1155
    name            VARCHAR(200),
    symbol          VARCHAR(50),
    decimals        INTEGER,
    total_supply    NUMERIC(78),

    -- Metadata
    icon_url        TEXT,
    website         TEXT,

    -- Stats
    holder_count    BIGINT DEFAULT 0,
    transfer_count  BIGINT DEFAULT 0,

    -- Timestamps
    created_at_block BIGINT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE (chain_id, address)
);

-- Token transfers
CREATE TABLE token_transfers (
    id              BIGSERIAL,
    chain_id        BIGINT NOT NULL,
    transaction_hash BYTEA NOT NULL,
    log_index       INTEGER NOT NULL,
    block_number    BIGINT NOT NULL,

    -- Transfer info
    token_address   BYTEA NOT NULL,
    from_address    BYTEA NOT NULL,
    to_address      BYTEA NOT NULL,
    value           NUMERIC(78),  -- For ERC-20
    token_id        NUMERIC(78),  -- For ERC-721/1155

    -- Metadata
    token_type      VARCHAR(20) NOT NULL,
    timestamp       BIGINT NOT NULL,
    indexed_at      TIMESTAMPTZ DEFAULT NOW(),

    PRIMARY KEY (chain_id, transaction_hash, log_index)
) PARTITION BY LIST (chain_id);

CREATE TABLE token_transfers_96369 PARTITION OF token_transfers FOR VALUES IN (96369);
CREATE TABLE token_transfers_200200 PARTITION OF token_transfers FOR VALUES IN (200200);
CREATE TABLE token_transfers_36963 PARTITION OF token_transfers FOR VALUES IN (36963);

-- Token balances (current state)
CREATE TABLE token_balances (
    id              BIGSERIAL,
    chain_id        BIGINT NOT NULL,
    token_address   BYTEA NOT NULL,
    holder_address  BYTEA NOT NULL,

    -- Balance
    balance         NUMERIC(78) NOT NULL DEFAULT 0,
    token_id        NUMERIC(78),  -- For ERC-721/1155

    -- Timestamps
    last_block      BIGINT NOT NULL,
    updated_at      TIMESTAMPTZ DEFAULT NOW(),

    PRIMARY KEY (chain_id, token_address, holder_address, COALESCE(token_id, 0))
) PARTITION BY LIST (chain_id);

CREATE TABLE token_balances_96369 PARTITION OF token_balances FOR VALUES IN (96369);
CREATE TABLE token_balances_200200 PARTITION OF token_balances FOR VALUES IN (200200);
CREATE TABLE token_balances_36963 PARTITION OF token_balances FOR VALUES IN (36963);

-- Indexer checkpoints
CREATE TABLE indexer_checkpoints (
    id              SERIAL PRIMARY KEY,
    chain_id        BIGINT NOT NULL,
    component       VARCHAR(50) NOT NULL,  -- blocks, traces, logs, tokens

    -- Progress
    last_block      BIGINT NOT NULL,
    last_hash       BYTEA,

    -- Stats
    blocks_indexed  BIGINT DEFAULT 0,
    errors          INTEGER DEFAULT 0,

    -- Timestamps
    started_at      TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE (chain_id, component)
);

-- Statistics (aggregated)
CREATE TABLE chain_stats (
    id              SERIAL PRIMARY KEY,
    chain_id        BIGINT NOT NULL REFERENCES chains(chain_id),
    date            DATE NOT NULL,

    -- Block stats
    block_count     BIGINT DEFAULT 0,
    avg_block_time  NUMERIC(10, 2),
    avg_block_size  BIGINT,

    -- Transaction stats
    transaction_count BIGINT DEFAULT 0,
    avg_gas_price   NUMERIC(78),
    avg_gas_used    NUMERIC(78),
    total_gas_used  NUMERIC(78),

    -- Address stats
    new_addresses   BIGINT DEFAULT 0,
    active_addresses BIGINT DEFAULT 0,

    -- Token stats
    token_transfers BIGINT DEFAULT 0,
    new_tokens      BIGINT DEFAULT 0,

    -- Contract stats
    contracts_deployed BIGINT DEFAULT 0,
    contracts_verified BIGINT DEFAULT 0,

    UNIQUE (chain_id, date)
);

-- Method/event signatures database
CREATE TABLE signatures (
    id              SERIAL PRIMARY KEY,
    hash            BYTEA NOT NULL,  -- 4 bytes for methods, 32 for events
    type            VARCHAR(10) NOT NULL,  -- method, event
    text_signature  TEXT NOT NULL,

    -- Metadata
    created_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE (hash, type)
);
```

### Index Definitions

```sql
-- migrations/002_indexes.sql

-- Block indexes
CREATE INDEX idx_blocks_hash ON blocks USING HASH (hash);
CREATE INDEX idx_blocks_timestamp ON blocks (chain_id, timestamp DESC);
CREATE INDEX idx_blocks_miner ON blocks (chain_id, miner);

-- Transaction indexes
CREATE INDEX idx_transactions_block ON transactions (chain_id, block_number);
CREATE INDEX idx_transactions_from ON transactions (chain_id, from_address);
CREATE INDEX idx_transactions_to ON transactions (chain_id, to_address);
CREATE INDEX idx_transactions_created ON transactions (chain_id, created_contract) WHERE created_contract IS NOT NULL;
CREATE INDEX idx_transactions_timestamp ON transactions (chain_id, timestamp DESC);
CREATE INDEX idx_transactions_status ON transactions (chain_id, status) WHERE status = 0;

-- Internal transaction indexes
CREATE INDEX idx_internal_tx_block ON internal_transactions (chain_id, block_number);
CREATE INDEX idx_internal_tx_from ON internal_transactions (chain_id, from_address);
CREATE INDEX idx_internal_tx_to ON internal_transactions (chain_id, to_address);
CREATE INDEX idx_internal_tx_created ON internal_transactions (chain_id, created_contract) WHERE created_contract IS NOT NULL;

-- Log indexes (critical for filtering)
CREATE INDEX idx_logs_address ON logs (chain_id, address);
CREATE INDEX idx_logs_topic0 ON logs (chain_id, topic0);
CREATE INDEX idx_logs_topic0_address ON logs (chain_id, topic0, address);
CREATE INDEX idx_logs_block_range ON logs (chain_id, block_number);
CREATE INDEX idx_logs_transaction ON logs (chain_id, transaction_hash);

-- Combined topic indexes for common patterns
CREATE INDEX idx_logs_topics_012 ON logs (chain_id, topic0, topic1, topic2) WHERE topic0 IS NOT NULL;

-- Address indexes
CREATE INDEX idx_addresses_balance ON addresses (chain_id, balance DESC) WHERE balance > 0;
CREATE INDEX idx_addresses_contract ON addresses (chain_id) WHERE is_contract = TRUE;
CREATE INDEX idx_addresses_verified ON addresses (chain_id) WHERE is_verified = TRUE;
CREATE INDEX idx_addresses_name ON addresses USING GIN (name gin_trgm_ops) WHERE name IS NOT NULL;

-- Token indexes
CREATE INDEX idx_tokens_type ON tokens (chain_id, type);
CREATE INDEX idx_tokens_symbol ON tokens USING GIN (symbol gin_trgm_ops);
CREATE INDEX idx_tokens_name ON tokens USING GIN (name gin_trgm_ops);
CREATE INDEX idx_tokens_holders ON tokens (chain_id, holder_count DESC);

-- Token transfer indexes
CREATE INDEX idx_token_transfers_token ON token_transfers (chain_id, token_address);
CREATE INDEX idx_token_transfers_from ON token_transfers (chain_id, from_address);
CREATE INDEX idx_token_transfers_to ON token_transfers (chain_id, to_address);
CREATE INDEX idx_token_transfers_block ON token_transfers (chain_id, block_number DESC);

-- Token balance indexes
CREATE INDEX idx_token_balances_holder ON token_balances (chain_id, holder_address);
CREATE INDEX idx_token_balances_token_holder ON token_balances (chain_id, token_address, balance DESC);

-- Signature indexes
CREATE INDEX idx_signatures_hash ON signatures USING HASH (hash);

-- Verification indexes
CREATE INDEX idx_verifications_address ON contract_verifications (chain_id, address);
```

---

## 4. Indexer Pipeline

### Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                              INDEXER PIPELINE                                                           │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                                         │
│  STAGE 1: BLOCK FETCHING                                                                                               │
│  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                                   │  │
│  │   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                                                        │  │
│  │   │  Head       │     │  Backfill   │     │  Gap        │     Parallel fetchers with rate limiting              │  │
│  │   │  Tracker    │     │  Fetcher    │     │  Filler     │     Batch size: 100 blocks                            │  │
│  │   │  (realtime) │     │  (historic) │     │  (missing)  │     Concurrency: 32 workers                           │  │
│  │   └──────┬──────┘     └──────┬──────┘     └──────┬──────┘                                                        │  │
│  │          │                   │                   │                                                               │  │
│  └──────────┼───────────────────┼───────────────────┼───────────────────────────────────────────────────────────────┘  │
│             │                   │                   │                                                                   │
│             ▼                   ▼                   ▼                                                                   │
│         ┌───────────────────────────────────────────────────────────────────────┐                                      │
│         │                        BLOCK BUFFER (bounded channel)                  │                                      │
│         │                        Capacity: 10,000 blocks                         │                                      │
│         └───────────────────────────────────────────┬───────────────────────────┘                                      │
│                                                     │                                                                   │
│  STAGE 2: TRANSACTION PROCESSING                    ▼                                                                   │
│  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                                   │  │
│  │   For each block:                                                                                                │  │
│  │   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                                   │  │
│  │   │  Fetch      │────▶│  Fetch      │────▶│  Extract    │────▶│  Build      │                                   │  │
│  │   │  Receipts   │     │  Traces     │     │  Logs       │     │  Records    │                                   │  │
│  │   │  (batch)    │     │  (debug_*)  │     │  (decode)   │     │  (struct)   │                                   │  │
│  │   └─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘                                   │  │
│  │                                                                                                                   │  │
│  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                     │                                                                   │
│  STAGE 3: TOKEN TRACKING                            ▼                                                                   │
│  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                                   │  │
│  │   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                                                        │  │
│  │   │  Detect     │────▶│  Fetch      │────▶│  Update     │                                                        │  │
│  │   │  Transfers  │     │  Metadata   │     │  Balances   │                                                        │  │
│  │   │  (logs)     │     │  (name/sym) │     │  (state)    │                                                        │  │
│  │   └─────────────┘     └─────────────┘     └─────────────┘                                                        │  │
│  │                                                                                                                   │  │
│  │   Known signatures:                                                                                              │  │
│  │   - 0xddf252ad... Transfer(address,address,uint256)  [ERC-20/721]                                               │  │
│  │   - 0xc3d58168... TransferSingle(...)                [ERC-1155]                                                 │  │
│  │   - 0x4a39dc06... TransferBatch(...)                 [ERC-1155]                                                 │  │
│  │                                                                                                                   │  │
│  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                     │                                                                   │
│  STAGE 4: BATCH WRITE                               ▼                                                                   │
│  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                                   │  │
│  │   ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐   │  │
│  │   │                              BATCH WRITER (PostgreSQL COPY)                                              │   │  │
│  │   │                                                                                                          │   │  │
│  │   │   Batch size: 1,000 records      Flush interval: 1 second      Transaction: SERIALIZABLE               │   │  │
│  │   │                                                                                                          │   │  │
│  │   │   Tables written per batch:                                                                              │   │  │
│  │   │   ├── blocks            ├── transactions         ├── logs                                               │   │  │
│  │   │   ├── internal_txs      ├── token_transfers      ├── token_balances (UPSERT)                           │   │  │
│  │   │   └── addresses (UPSERT)                                                                                 │   │  │
│  │   │                                                                                                          │   │  │
│  │   └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │  │
│  │                                                     │                                                            │  │
│  │                                                     ▼                                                            │  │
│  │   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                                                       │  │
│  │   │  Update     │     │  Publish    │     │  Checkpoint │                                                       │  │
│  │   │  Cache      │     │  Events     │     │  Progress   │                                                       │  │
│  │   │  (Redis)    │     │  (Pub/Sub)  │     │  (atomic)   │                                                       │  │
│  │   └─────────────┘     └─────────────┘     └─────────────┘                                                       │  │
│  │                                                                                                                   │  │
│  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                                         │
│  STAGE 5: REORG HANDLING                                                                                               │
│  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                                   │  │
│  │   Reorg Detection:                                                                                               │  │
│  │   1. Compare incoming block.parentHash with stored block[n-1].hash                                              │  │
│  │   2. If mismatch, walk back to find common ancestor                                                             │  │
│  │   3. Mark orphaned blocks/txs as "removed"                                                                      │  │
│  │   4. Re-index from common ancestor                                                                               │  │
│  │                                                                                                                   │  │
│  │   ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │  │
│  │   │  Canonical:   ... ─── Block N-3 ─── Block N-2 ─── Block N-1 ─── Block N                                 │  │  │
│  │   │                          │                                                                                │  │  │
│  │   │  Orphaned:               └─── Block N-2' ─── Block N-1' ─── Block N'  (marked removed=true)             │  │  │
│  │   └──────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                                                                   │  │
│  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Coordinator Implementation

```go
// internal/indexer/coordinator.go

package indexer

import (
    "context"
    "sync"
    "time"

    "github.com/luxfi/indexer/internal/chain"
    "github.com/luxfi/indexer/internal/storage"
    "github.com/luxfi/indexer/internal/metrics"
)

type Coordinator struct {
    config      *Config
    chainClient chain.Client
    storage     storage.Storage

    // Pipeline stages
    fetcher     *Fetcher
    processor   *Processor
    decoder     *Decoder
    tracker     *TokenTracker
    writer      *Writer

    // Channels
    blockChan   chan *chain.Block
    recordChan  chan *Records

    // State
    checkpoint  *Checkpoint
    mu          sync.RWMutex

    // Metrics
    metrics     *metrics.Collector

    // Control
    ctx         context.Context
    cancel      context.CancelFunc
    wg          sync.WaitGroup
}

type Config struct {
    ChainID         uint64
    RPCEndpoints    []string
    BatchSize       int           // Blocks per batch
    Workers         int           // Parallel workers
    BufferSize      int           // Block buffer capacity
    FlushInterval   time.Duration // DB flush interval
    ReorgDepth      int           // Max reorg depth to handle
    TraceEnabled    bool          // Enable trace indexing
    TokenTrackingEnabled bool     // Enable token tracking
}

func NewCoordinator(cfg *Config, storage storage.Storage) (*Coordinator, error) {
    ctx, cancel := context.WithCancel(context.Background())

    c := &Coordinator{
        config:     cfg,
        storage:    storage,
        blockChan:  make(chan *chain.Block, cfg.BufferSize),
        recordChan: make(chan *Records, cfg.BufferSize),
        ctx:        ctx,
        cancel:     cancel,
        metrics:    metrics.NewCollector("indexer"),
    }

    // Initialize RPC client pool
    client, err := chain.NewClientPool(cfg.RPCEndpoints, cfg.Workers)
    if err != nil {
        return nil, err
    }
    c.chainClient = client

    // Initialize pipeline stages
    c.fetcher = NewFetcher(client, cfg.BatchSize, cfg.Workers)
    c.processor = NewProcessor(client, cfg.TraceEnabled)
    c.decoder = NewDecoder()
    c.tracker = NewTokenTracker(client, storage)
    c.writer = NewWriter(storage, cfg.FlushInterval)

    // Load checkpoint
    c.checkpoint, err = c.storage.GetCheckpoint(ctx, cfg.ChainID)
    if err != nil {
        return nil, err
    }

    return c, nil
}

func (c *Coordinator) Start() error {
    // Start head tracker (real-time)
    c.wg.Add(1)
    go c.runHeadTracker()

    // Start backfill (historic)
    c.wg.Add(1)
    go c.runBackfill()

    // Start processors
    for i := 0; i < c.config.Workers; i++ {
        c.wg.Add(1)
        go c.runProcessor()
    }

    // Start writer
    c.wg.Add(1)
    go c.runWriter()

    // Start gap filler (background)
    c.wg.Add(1)
    go c.runGapFiller()

    return nil
}

func (c *Coordinator) runHeadTracker() {
    defer c.wg.Done()

    sub, err := c.chainClient.SubscribeNewHead(c.ctx)
    if err != nil {
        c.metrics.RecordError("head_subscription")
        return
    }
    defer sub.Unsubscribe()

    for {
        select {
        case <-c.ctx.Done():
            return
        case header := <-sub.Headers():
            c.metrics.RecordBlockReceived(header.Number.Uint64())

            // Check for reorg
            if c.detectReorg(header) {
                c.handleReorg(header)
                continue
            }

            // Fetch full block
            block, err := c.chainClient.GetBlockByNumber(c.ctx, header.Number.Uint64())
            if err != nil {
                c.metrics.RecordError("fetch_block")
                continue
            }

            select {
            case c.blockChan <- block:
            case <-c.ctx.Done():
                return
            }
        }
    }
}

func (c *Coordinator) runBackfill() {
    defer c.wg.Done()

    // Determine range to backfill
    latestBlock, err := c.chainClient.GetLatestBlockNumber(c.ctx)
    if err != nil {
        return
    }

    startBlock := c.checkpoint.LastBlock + 1
    if startBlock > latestBlock {
        return // Already caught up
    }

    // Backfill in batches
    for start := startBlock; start <= latestBlock; start += uint64(c.config.BatchSize) {
        select {
        case <-c.ctx.Done():
            return
        default:
        }

        end := min(start+uint64(c.config.BatchSize)-1, latestBlock)

        blocks, err := c.fetcher.FetchRange(c.ctx, start, end)
        if err != nil {
            c.metrics.RecordError("fetch_range")
            continue
        }

        for _, block := range blocks {
            select {
            case c.blockChan <- block:
            case <-c.ctx.Done():
                return
            }
        }

        c.metrics.RecordBackfillProgress(start, end, latestBlock)
    }
}

func (c *Coordinator) runProcessor() {
    defer c.wg.Done()

    for {
        select {
        case <-c.ctx.Done():
            return
        case block := <-c.blockChan:
            records, err := c.processBlock(block)
            if err != nil {
                c.metrics.RecordError("process_block")
                continue
            }

            select {
            case c.recordChan <- records:
            case <-c.ctx.Done():
                return
            }
        }
    }
}

func (c *Coordinator) processBlock(block *chain.Block) (*Records, error) {
    timer := c.metrics.StartTimer("process_block")
    defer timer.Stop()

    records := &Records{
        Block: block,
    }

    // Fetch receipts (batch)
    receipts, err := c.chainClient.GetBlockReceipts(c.ctx, block.Number)
    if err != nil {
        return nil, err
    }

    // Process transactions
    for i, tx := range block.Transactions {
        txRecord := c.processor.ProcessTransaction(tx, receipts[i], block)
        records.Transactions = append(records.Transactions, txRecord)

        // Process logs
        for _, log := range receipts[i].Logs {
            logRecord := c.decoder.DecodeLog(log)
            records.Logs = append(records.Logs, logRecord)

            // Track token transfers
            if c.config.TokenTrackingEnabled {
                transfer := c.tracker.DetectTransfer(log)
                if transfer != nil {
                    records.TokenTransfers = append(records.TokenTransfers, transfer)
                }
            }
        }
    }

    // Fetch traces if enabled
    if c.config.TraceEnabled {
        traces, err := c.chainClient.TraceBlock(c.ctx, block.Number)
        if err != nil {
            c.metrics.RecordError("trace_block")
        } else {
            records.InternalTxs = c.processor.ProcessTraces(traces, block)
        }
    }

    return records, nil
}

func (c *Coordinator) runWriter() {
    defer c.wg.Done()

    batch := make([]*Records, 0, c.config.BatchSize)
    ticker := time.NewTicker(c.config.FlushInterval)
    defer ticker.Stop()

    flush := func() {
        if len(batch) == 0 {
            return
        }

        timer := c.metrics.StartTimer("write_batch")
        if err := c.writer.WriteBatch(c.ctx, batch); err != nil {
            c.metrics.RecordError("write_batch")
        }
        timer.Stop()

        // Update checkpoint
        lastBlock := batch[len(batch)-1].Block.Number
        c.checkpoint.LastBlock = lastBlock
        c.storage.UpdateCheckpoint(c.ctx, c.checkpoint)

        // Publish events
        c.publishEvents(batch)

        c.metrics.RecordBlocksWritten(uint64(len(batch)))
        batch = batch[:0]
    }

    for {
        select {
        case <-c.ctx.Done():
            flush()
            return
        case records := <-c.recordChan:
            batch = append(batch, records)
            if len(batch) >= c.config.BatchSize {
                flush()
            }
        case <-ticker.C:
            flush()
        }
    }
}

func (c *Coordinator) detectReorg(header *chain.Header) bool {
    c.mu.RLock()
    lastHash := c.checkpoint.LastHash
    c.mu.RUnlock()

    if lastHash == nil {
        return false
    }

    return header.ParentHash != *lastHash
}

func (c *Coordinator) handleReorg(header *chain.Header) {
    c.metrics.RecordReorg()

    // Find common ancestor
    current := header
    depth := 0

    for depth < c.config.ReorgDepth {
        storedBlock, err := c.storage.GetBlockByNumber(c.ctx, current.Number.Uint64()-1)
        if err != nil {
            break
        }

        if storedBlock.Hash == current.ParentHash {
            // Found common ancestor
            break
        }

        // Mark as orphaned
        c.storage.MarkBlockOrphaned(c.ctx, storedBlock.Number)

        // Get parent
        parent, err := c.chainClient.GetBlockByHash(c.ctx, current.ParentHash)
        if err != nil {
            break
        }
        current = parent.Header
        depth++
    }

    // Update checkpoint to re-index
    c.mu.Lock()
    c.checkpoint.LastBlock = current.Number.Uint64() - 1
    c.mu.Unlock()
}

func (c *Coordinator) runGapFiller() {
    defer c.wg.Done()

    ticker := time.NewTicker(5 * time.Minute)
    defer ticker.Stop()

    for {
        select {
        case <-c.ctx.Done():
            return
        case <-ticker.C:
            gaps, err := c.storage.FindGaps(c.ctx, c.config.ChainID)
            if err != nil {
                continue
            }

            for _, gap := range gaps {
                blocks, err := c.fetcher.FetchRange(c.ctx, gap.Start, gap.End)
                if err != nil {
                    continue
                }

                for _, block := range blocks {
                    select {
                    case c.blockChan <- block:
                    case <-c.ctx.Done():
                        return
                    }
                }
            }
        }
    }
}

func (c *Coordinator) publishEvents(batch []*Records) {
    for _, records := range batch {
        // Publish new block event
        c.storage.PublishEvent(c.ctx, &Event{
            Type:    "new_block",
            ChainID: c.config.ChainID,
            Data:    records.Block,
        })

        // Publish transaction events
        for _, tx := range records.Transactions {
            c.storage.PublishEvent(c.ctx, &Event{
                Type:    "new_transaction",
                ChainID: c.config.ChainID,
                Data:    tx,
            })
        }

        // Publish token transfer events
        for _, transfer := range records.TokenTransfers {
            c.storage.PublishEvent(c.ctx, &Event{
                Type:    "token_transfer",
                ChainID: c.config.ChainID,
                Data:    transfer,
            })
        }
    }
}

func (c *Coordinator) Stop() {
    c.cancel()
    c.wg.Wait()
}
```

---

## 5. API Layer

### REST API (Etherscan Compatible)

```go
// internal/api/rest/etherscan/router.go

package etherscan

import (
    "github.com/go-chi/chi/v5"
    "github.com/luxfi/indexer/internal/storage"
)

type Handler struct {
    storage storage.Storage
    cache   *redis.Client
}

func NewHandler(storage storage.Storage, cache *redis.Client) *Handler {
    return &Handler{storage: storage, cache: cache}
}

func (h *Handler) Routes() chi.Router {
    r := chi.NewRouter()

    // Etherscan API v1 compatible endpoints
    r.Get("/api", h.handleAPI)

    return r
}

func (h *Handler) handleAPI(w http.ResponseWriter, r *http.Request) {
    module := r.URL.Query().Get("module")
    action := r.URL.Query().Get("action")

    switch module {
    case "account":
        h.handleAccount(w, r, action)
    case "contract":
        h.handleContract(w, r, action)
    case "transaction":
        h.handleTransaction(w, r, action)
    case "block":
        h.handleBlock(w, r, action)
    case "logs":
        h.handleLogs(w, r, action)
    case "token":
        h.handleToken(w, r, action)
    case "stats":
        h.handleStats(w, r, action)
    case "proxy":
        h.handleProxy(w, r, action)
    default:
        h.errorResponse(w, "Unknown module")
    }
}

// Account module
func (h *Handler) handleAccount(w http.ResponseWriter, r *http.Request, action string) {
    switch action {
    case "balance":
        h.getBalance(w, r)
    case "balancemulti":
        h.getBalanceMulti(w, r)
    case "txlist":
        h.getTxList(w, r)
    case "txlistinternal":
        h.getTxListInternal(w, r)
    case "tokentx":
        h.getTokenTx(w, r)
    case "tokennfttx":
        h.getTokenNftTx(w, r)
    case "token1155tx":
        h.getToken1155Tx(w, r)
    case "getminedblocks":
        h.getMinedBlocks(w, r)
    }
}

// Transaction list with full Etherscan compatibility
func (h *Handler) getTxList(w http.ResponseWriter, r *http.Request) {
    address := r.URL.Query().Get("address")
    startBlock := parseUint64(r.URL.Query().Get("startblock"), 0)
    endBlock := parseUint64(r.URL.Query().Get("endblock"), 99999999)
    page := parseInt(r.URL.Query().Get("page"), 1)
    offset := parseInt(r.URL.Query().Get("offset"), 10)
    sort := r.URL.Query().Get("sort") // "asc" or "desc"

    // Validate
    if !isValidAddress(address) {
        h.errorResponse(w, "Invalid address format")
        return
    }

    if offset > 10000 {
        offset = 10000 // Etherscan max
    }

    // Query
    txs, err := h.storage.GetTransactionsByAddress(r.Context(), address, &storage.QueryOptions{
        StartBlock: &startBlock,
        EndBlock:   &endBlock,
        Offset:     (page - 1) * offset,
        Limit:      offset,
        Sort:       sort,
    })
    if err != nil {
        h.errorResponse(w, err.Error())
        return
    }

    // Format response (Etherscan format)
    result := make([]map[string]interface{}, len(txs))
    for i, tx := range txs {
        result[i] = h.formatTransaction(tx)
    }

    h.successResponse(w, result)
}

// Etherscan response format
func (h *Handler) successResponse(w http.ResponseWriter, result interface{}) {
    json.NewEncoder(w).Encode(map[string]interface{}{
        "status":  "1",
        "message": "OK",
        "result":  result,
    })
}

func (h *Handler) errorResponse(w http.ResponseWriter, message string) {
    json.NewEncoder(w).Encode(map[string]interface{}{
        "status":  "0",
        "message": "NOTOK",
        "result":  message,
    })
}

// Format transaction in Etherscan format
func (h *Handler) formatTransaction(tx *types.Transaction) map[string]interface{} {
    return map[string]interface{}{
        "blockNumber":       fmt.Sprintf("%d", tx.BlockNumber),
        "timeStamp":         fmt.Sprintf("%d", tx.Timestamp),
        "hash":              tx.Hash,
        "nonce":             fmt.Sprintf("%d", tx.Nonce),
        "blockHash":         tx.BlockHash,
        "transactionIndex":  fmt.Sprintf("%d", tx.TransactionIndex),
        "from":              tx.From,
        "to":                tx.To,
        "value":             tx.Value.String(),
        "gas":               fmt.Sprintf("%d", tx.Gas),
        "gasPrice":          tx.GasPrice.String(),
        "isError":           boolToString(tx.Status == 0),
        "txreceipt_status":  fmt.Sprintf("%d", tx.Status),
        "input":             hexutil.Encode(tx.Input),
        "contractAddress":   tx.CreatedContract,
        "cumulativeGasUsed": fmt.Sprintf("%d", tx.CumulativeGasUsed),
        "gasUsed":           fmt.Sprintf("%d", tx.GasUsed),
        "confirmations":     fmt.Sprintf("%d", tx.Confirmations),
        "methodId":          h.getMethodId(tx.Input),
        "functionName":      h.getFunctionName(tx.Input),
    }
}
```

### GraphQL Schema

```graphql
# api/graphql/schema.graphql

type Query {
    # Block queries
    block(number: Long, hash: String): Block
    blocks(first: Int, after: String, orderBy: BlockOrderBy): BlockConnection!

    # Transaction queries
    transaction(hash: String!): Transaction
    transactions(
        first: Int
        after: String
        address: String
        fromBlock: Long
        toBlock: Long
    ): TransactionConnection!

    # Log queries
    logs(filter: LogFilter!): [Log!]!

    # Account queries
    account(address: String!): Account
    accounts(first: Int, after: String, orderBy: AccountOrderBy): AccountConnection!

    # Token queries
    token(address: String!): Token
    tokens(first: Int, after: String, type: TokenType): TokenConnection!
    tokenTransfers(
        first: Int
        after: String
        tokenAddress: String
        address: String
    ): TokenTransferConnection!

    # Contract queries
    contract(address: String!): Contract

    # Stats
    stats: ChainStats!
}

type Subscription {
    # Real-time subscriptions
    newBlocks: Block!
    newTransactions(address: String): Transaction!
    newLogs(filter: LogFilter): Log!
    pendingTransactions: Transaction!
}

type Block {
    number: Long!
    hash: String!
    parentHash: String!
    timestamp: Long!
    miner: String!
    difficulty: BigInt!
    totalDifficulty: BigInt
    size: Int!
    gasLimit: Long!
    gasUsed: Long!
    baseFeePerGas: BigInt
    transactionCount: Int!

    # Lux-specific
    extDataHash: String
    extDataGasUsed: Long
    blockGasCost: BigInt

    # Relations
    transactions: [Transaction!]!
    logs: [Log!]!
}

type Transaction {
    hash: String!
    blockNumber: Long!
    blockHash: String!
    transactionIndex: Int!
    from: Account!
    to: Account
    value: BigInt!
    gas: Long!
    gasPrice: BigInt!
    gasUsed: Long
    maxFeePerGas: BigInt
    maxPriorityFeePerGas: BigInt
    effectiveGasPrice: BigInt
    input: String!
    nonce: Long!
    type: Int!
    status: Int

    # Contract creation
    createdContract: Contract

    # Relations
    block: Block!
    logs: [Log!]!
    internalTransactions: [InternalTransaction!]!
    tokenTransfers: [TokenTransfer!]!
}

type Log {
    logIndex: Int!
    transactionHash: String!
    transactionIndex: Int!
    blockNumber: Long!
    blockHash: String!
    address: String!
    data: String!
    topics: [String!]!
    removed: Boolean!

    # Decoded event (if ABI available)
    decodedName: String
    decodedParams: JSON

    # Relations
    transaction: Transaction!
    block: Block!
}

type Account {
    address: String!
    balance: BigInt!
    transactionCount: Long!
    isContract: Boolean!

    # Contract info (if is_contract)
    contract: Contract

    # Token balances
    tokenBalances: [TokenBalance!]!

    # Transactions
    transactions(first: Int, after: String): TransactionConnection!
    internalTransactions(first: Int, after: String): InternalTransactionConnection!
}

type Token {
    address: String!
    type: TokenType!
    name: String
    symbol: String
    decimals: Int
    totalSupply: BigInt
    holderCount: Long!
    transferCount: Long!

    # Relations
    holders(first: Int, after: String): TokenHolderConnection!
    transfers(first: Int, after: String): TokenTransferConnection!
}

type TokenTransfer {
    transactionHash: String!
    logIndex: Int!
    tokenAddress: String!
    from: String!
    to: String!
    value: BigInt
    tokenId: BigInt
    tokenType: TokenType!
    timestamp: Long!

    # Relations
    token: Token!
    transaction: Transaction!
}

type Contract {
    address: String!
    createdBy: String
    createdAtBlock: Long
    createdAtTransaction: String
    bytecode: String!

    # Verification
    isVerified: Boolean!
    name: String
    compilerVersion: String
    optimization: Boolean
    sourceCode: String
    abi: JSON

    # Relations
    transactions(first: Int, after: String): TransactionConnection!
}

type ChainStats {
    blockCount: Long!
    transactionCount: Long!
    addressCount: Long!
    averageBlockTime: Float!
    gasPrice: BigInt!

    # 24h stats
    blocksToday: Int!
    transactionsToday: Long!
    averageGasUsed: BigInt!
}

# Enums
enum TokenType {
    ERC20
    ERC721
    ERC1155
}

enum BlockOrderBy {
    NUMBER_ASC
    NUMBER_DESC
    TIMESTAMP_ASC
    TIMESTAMP_DESC
}

enum AccountOrderBy {
    BALANCE_DESC
    BALANCE_ASC
    TX_COUNT_DESC
}

# Input types
input LogFilter {
    address: [String!]
    topics: [[String]]
    fromBlock: Long
    toBlock: Long
}

# Scalars
scalar Long
scalar BigInt
scalar JSON

# Pagination
type PageInfo {
    hasNextPage: Boolean!
    hasPreviousPage: Boolean!
    startCursor: String
    endCursor: String
}

type BlockConnection {
    edges: [BlockEdge!]!
    pageInfo: PageInfo!
    totalCount: Long!
}

type BlockEdge {
    node: Block!
    cursor: String!
}

# ... similar for TransactionConnection, AccountConnection, etc.
```

### GraphQL Resolvers

```go
// internal/api/graphql/resolvers.go

package graphql

import (
    "context"

    "github.com/graph-gophers/graphql-go"
    "github.com/luxfi/indexer/internal/storage"
    "github.com/luxfi/indexer/pkg/types"
)

type Resolver struct {
    storage storage.Storage
    loader  *DataLoader
}

func NewResolver(storage storage.Storage) *Resolver {
    return &Resolver{
        storage: storage,
        loader:  NewDataLoader(storage),
    }
}

// Block resolver
func (r *Resolver) Block(ctx context.Context, args struct {
    Number *graphql.ID
    Hash   *string
}) (*BlockResolver, error) {
    var block *types.Block
    var err error

    if args.Number != nil {
        num, _ := strconv.ParseUint(string(*args.Number), 10, 64)
        block, err = r.storage.GetBlockByNumber(ctx, num)
    } else if args.Hash != nil {
        block, err = r.storage.GetBlockByHash(ctx, *args.Hash)
    }

    if err != nil || block == nil {
        return nil, err
    }

    return &BlockResolver{block: block, loader: r.loader}, nil
}

// Blocks with pagination
func (r *Resolver) Blocks(ctx context.Context, args struct {
    First   *int32
    After   *string
    OrderBy *string
}) (*BlockConnectionResolver, error) {
    opts := &storage.QueryOptions{
        Limit: int(deref(args.First, 10)),
    }

    if args.After != nil {
        cursor, _ := decodeCursor(*args.After)
        opts.Offset = cursor.Offset
    }

    if args.OrderBy != nil {
        switch *args.OrderBy {
        case "NUMBER_DESC":
            opts.Sort = "desc"
            opts.SortBy = "number"
        case "NUMBER_ASC":
            opts.Sort = "asc"
            opts.SortBy = "number"
        }
    }

    blocks, total, err := r.storage.GetBlocks(ctx, opts)
    if err != nil {
        return nil, err
    }

    return &BlockConnectionResolver{
        blocks:     blocks,
        totalCount: total,
        offset:     opts.Offset,
        limit:      opts.Limit,
        loader:     r.loader,
    }, nil
}

// Transaction resolver
func (r *Resolver) Transaction(ctx context.Context, args struct{ Hash string }) (*TransactionResolver, error) {
    tx, err := r.storage.GetTransactionByHash(ctx, args.Hash)
    if err != nil {
        return nil, err
    }
    return &TransactionResolver{tx: tx, loader: r.loader}, nil
}

// Account resolver
func (r *Resolver) Account(ctx context.Context, args struct{ Address string }) (*AccountResolver, error) {
    account, err := r.storage.GetAddress(ctx, args.Address)
    if err != nil {
        return nil, err
    }
    return &AccountResolver{account: account, loader: r.loader}, nil
}

// Logs resolver with filter
func (r *Resolver) Logs(ctx context.Context, args struct{ Filter LogFilterInput }) ([]*LogResolver, error) {
    filter := &types.LogFilter{
        Addresses:  args.Filter.Address,
        Topics:     args.Filter.Topics,
        FromBlock:  args.Filter.FromBlock,
        ToBlock:    args.Filter.ToBlock,
    }

    logs, err := r.storage.GetLogsByFilter(ctx, filter)
    if err != nil {
        return nil, err
    }

    resolvers := make([]*LogResolver, len(logs))
    for i, log := range logs {
        resolvers[i] = &LogResolver{log: log, loader: r.loader}
    }
    return resolvers, nil
}

// BlockResolver
type BlockResolver struct {
    block  *types.Block
    loader *DataLoader
}

func (r *BlockResolver) Number() graphql.ID {
    return graphql.ID(fmt.Sprintf("%d", r.block.Number))
}

func (r *BlockResolver) Hash() string {
    return r.block.Hash
}

func (r *BlockResolver) Transactions(ctx context.Context) ([]*TransactionResolver, error) {
    txs, err := r.loader.LoadTransactionsByBlock(ctx, r.block.Number)
    if err != nil {
        return nil, err
    }

    resolvers := make([]*TransactionResolver, len(txs))
    for i, tx := range txs {
        resolvers[i] = &TransactionResolver{tx: tx, loader: r.loader}
    }
    return resolvers, nil
}

// DataLoader for N+1 prevention
type DataLoader struct {
    storage storage.Storage

    blockLoader       *dataloader.Loader
    transactionLoader *dataloader.Loader
    accountLoader     *dataloader.Loader
}

func NewDataLoader(storage storage.Storage) *DataLoader {
    dl := &DataLoader{storage: storage}

    dl.blockLoader = dataloader.NewBatchedLoader(dl.loadBlocks, dataloader.WithBatchCapacity(100))
    dl.transactionLoader = dataloader.NewBatchedLoader(dl.loadTransactions, dataloader.WithBatchCapacity(100))
    dl.accountLoader = dataloader.NewBatchedLoader(dl.loadAccounts, dataloader.WithBatchCapacity(100))

    return dl
}

func (dl *DataLoader) loadBlocks(ctx context.Context, keys dataloader.Keys) []*dataloader.Result {
    numbers := make([]uint64, len(keys))
    for i, key := range keys {
        numbers[i] = key.(uint64)
    }

    blocks, err := dl.storage.GetBlocksByNumbers(ctx, numbers)
    if err != nil {
        return errorResults(len(keys), err)
    }

    results := make([]*dataloader.Result, len(keys))
    for i, block := range blocks {
        results[i] = &dataloader.Result{Data: block}
    }
    return results
}
```

---

## 6. Real-time Subscriptions

### WebSocket Hub

```go
// internal/api/ws/hub.go

package ws

import (
    "context"
    "encoding/json"
    "sync"

    "github.com/gorilla/websocket"
    "github.com/luxfi/indexer/internal/storage"
)

type Hub struct {
    // Client management
    clients    map[*Client]bool
    register   chan *Client
    unregister chan *Client

    // Subscriptions
    subscriptions map[string]map[*Client]bool // topic -> clients
    mu            sync.RWMutex

    // Event source
    events <-chan *storage.Event

    // Control
    ctx    context.Context
    cancel context.CancelFunc
}

type Client struct {
    hub    *Hub
    conn   *websocket.Conn
    send   chan []byte
    subs   map[string]bool // subscribed topics
    chainID uint64
}

type Message struct {
    Type    string          `json:"type"`
    Topic   string          `json:"topic,omitempty"`
    Params  json.RawMessage `json:"params,omitempty"`
    Payload json.RawMessage `json:"payload,omitempty"`
}

type Subscription struct {
    Topic    string
    ChainID  uint64
    Address  string   // Optional: filter by address
    Topics   []string // Optional: filter by log topics
}

func NewHub(events <-chan *storage.Event) *Hub {
    ctx, cancel := context.WithCancel(context.Background())
    return &Hub{
        clients:       make(map[*Client]bool),
        register:      make(chan *Client),
        unregister:    make(chan *Client),
        subscriptions: make(map[string]map[*Client]bool),
        events:        events,
        ctx:           ctx,
        cancel:        cancel,
    }
}

func (h *Hub) Run() {
    for {
        select {
        case <-h.ctx.Done():
            return

        case client := <-h.register:
            h.clients[client] = true

        case client := <-h.unregister:
            if _, ok := h.clients[client]; ok {
                delete(h.clients, client)
                close(client.send)
                h.removeAllSubscriptions(client)
            }

        case event := <-h.events:
            h.broadcast(event)
        }
    }
}

func (h *Hub) broadcast(event *storage.Event) {
    topic := h.eventToTopic(event)

    h.mu.RLock()
    clients := h.subscriptions[topic]
    h.mu.RUnlock()

    if len(clients) == 0 {
        return
    }

    message, err := json.Marshal(&Message{
        Type:    "event",
        Topic:   topic,
        Payload: event.Data,
    })
    if err != nil {
        return
    }

    for client := range clients {
        if h.matchesSubscription(client, event) {
            select {
            case client.send <- message:
            default:
                // Client send buffer full, skip
            }
        }
    }
}

func (h *Hub) eventToTopic(event *storage.Event) string {
    return fmt.Sprintf("%d:%s", event.ChainID, event.Type)
}

func (h *Hub) matchesSubscription(client *Client, event *storage.Event) bool {
    if client.chainID != 0 && client.chainID != event.ChainID {
        return false
    }
    // Additional filtering based on client.subs
    return true
}

func (h *Hub) Subscribe(client *Client, sub *Subscription) {
    topic := fmt.Sprintf("%d:%s", sub.ChainID, sub.Topic)

    h.mu.Lock()
    defer h.mu.Unlock()

    if h.subscriptions[topic] == nil {
        h.subscriptions[topic] = make(map[*Client]bool)
    }
    h.subscriptions[topic][client] = true
    client.subs[topic] = true
}

func (h *Hub) Unsubscribe(client *Client, topic string) {
    h.mu.Lock()
    defer h.mu.Unlock()

    if clients, ok := h.subscriptions[topic]; ok {
        delete(clients, client)
    }
    delete(client.subs, topic)
}

func (h *Hub) removeAllSubscriptions(client *Client) {
    h.mu.Lock()
    defer h.mu.Unlock()

    for topic := range client.subs {
        if clients, ok := h.subscriptions[topic]; ok {
            delete(clients, client)
        }
    }
}

// Client goroutines
func (c *Client) readPump() {
    defer func() {
        c.hub.unregister <- c
        c.conn.Close()
    }()

    c.conn.SetReadLimit(maxMessageSize)
    c.conn.SetReadDeadline(time.Now().Add(pongWait))
    c.conn.SetPongHandler(func(string) error {
        c.conn.SetReadDeadline(time.Now().Add(pongWait))
        return nil
    })

    for {
        _, message, err := c.conn.ReadMessage()
        if err != nil {
            break
        }

        var msg Message
        if err := json.Unmarshal(message, &msg); err != nil {
            continue
        }

        c.handleMessage(&msg)
    }
}

func (c *Client) handleMessage(msg *Message) {
    switch msg.Type {
    case "subscribe":
        var sub Subscription
        json.Unmarshal(msg.Params, &sub)
        c.hub.Subscribe(c, &sub)

        c.sendAck(msg.Topic, "subscribed")

    case "unsubscribe":
        c.hub.Unsubscribe(c, msg.Topic)
        c.sendAck(msg.Topic, "unsubscribed")

    case "ping":
        c.send <- []byte(`{"type":"pong"}`)
    }
}

func (c *Client) writePump() {
    ticker := time.NewTicker(pingPeriod)
    defer func() {
        ticker.Stop()
        c.conn.Close()
    }()

    for {
        select {
        case message, ok := <-c.send:
            c.conn.SetWriteDeadline(time.Now().Add(writeWait))
            if !ok {
                c.conn.WriteMessage(websocket.CloseMessage, []byte{})
                return
            }

            w, err := c.conn.NextWriter(websocket.TextMessage)
            if err != nil {
                return
            }
            w.Write(message)

            // Batch pending messages
            n := len(c.send)
            for i := 0; i < n; i++ {
                w.Write(newline)
                w.Write(<-c.send)
            }

            if err := w.Close(); err != nil {
                return
            }

        case <-ticker.C:
            c.conn.SetWriteDeadline(time.Now().Add(writeWait))
            if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
                return
            }
        }
    }
}

func (c *Client) sendAck(topic, status string) {
    msg, _ := json.Marshal(&Message{
        Type:  "ack",
        Topic: topic,
        Payload: json.RawMessage(fmt.Sprintf(`{"status":"%s"}`, status)),
    })
    c.send <- msg
}
```

### Subscription Protocol

```
Client -> Server:
{
    "type": "subscribe",
    "topic": "new_blocks",
    "params": {
        "chainId": 96369
    }
}

Server -> Client (ack):
{
    "type": "ack",
    "topic": "new_blocks",
    "payload": {"status": "subscribed"}
}

Server -> Client (event):
{
    "type": "event",
    "topic": "96369:new_block",
    "payload": {
        "number": 1234567,
        "hash": "0x...",
        "timestamp": 1703505600,
        "transactionCount": 42
    }
}

Subscription Topics:
- new_blocks          - All new blocks
- new_transactions    - All new transactions
- pending_transactions - Pending mempool transactions
- address:{address}   - Transactions involving address
- token:{address}     - Token transfers for token
- logs:{filter}       - Log events matching filter
```

---

## 7. Contract Verification

### Verification Service

```go
// internal/verify/service.go

package verify

import (
    "context"
    "encoding/json"
    "fmt"
    "os/exec"

    "github.com/luxfi/indexer/internal/storage"
    "github.com/luxfi/indexer/pkg/types"
)

type Service struct {
    storage       storage.Storage
    compilerCache *CompilerCache
    sourcify      *SourcifyClient
}

type VerifyRequest struct {
    ChainID         uint64            `json:"chainId"`
    Address         string            `json:"address"`
    CompilerType    string            `json:"compilerType"`    // solidity, vyper
    CompilerVersion string            `json:"compilerVersion"` // 0.8.24+commit.xxx
    SourceCode      string            `json:"sourceCode"`      // Single file
    SourceFiles     map[string]string `json:"sourceFiles"`     // Multi-file
    ContractName    string            `json:"contractName"`
    Optimization    bool              `json:"optimization"`
    OptimizationRuns int              `json:"optimizationRuns"`
    EVMVersion      string            `json:"evmVersion"`
    ConstructorArgs string            `json:"constructorArguments"` // ABI-encoded
    Libraries       map[string]string `json:"libraries"`
}

type VerifyResult struct {
    Success      bool            `json:"success"`
    Address      string          `json:"address"`
    ContractName string          `json:"contractName"`
    ABI          json.RawMessage `json:"abi"`
    BytecodeHash string          `json:"bytecodeHash"`
    SourceCode   string          `json:"sourceCode"`
    Message      string          `json:"message,omitempty"`
}

func (s *Service) Verify(ctx context.Context, req *VerifyRequest) (*VerifyResult, error) {
    // Get deployed bytecode
    deployed, err := s.getDeployedBytecode(ctx, req.ChainID, req.Address)
    if err != nil {
        return nil, fmt.Errorf("failed to get deployed bytecode: %w", err)
    }

    // Compile source
    compiled, err := s.compile(ctx, req)
    if err != nil {
        return nil, fmt.Errorf("compilation failed: %w", err)
    }

    // Find matching contract
    var matchedContract *CompiledContract
    for name, contract := range compiled.Contracts {
        if req.ContractName != "" && name != req.ContractName {
            continue
        }

        // Compare bytecode (without metadata hash)
        if s.bytecodeMatches(deployed, contract.DeployedBytecode, req.ConstructorArgs) {
            matchedContract = contract
            break
        }
    }

    if matchedContract == nil {
        return &VerifyResult{
            Success: false,
            Message: "Bytecode does not match deployed contract",
        }, nil
    }

    // Store verification
    verification := &types.ContractVerification{
        ChainID:          req.ChainID,
        Address:          req.Address,
        CompilerType:     req.CompilerType,
        CompilerVersion:  req.CompilerVersion,
        ContractName:     matchedContract.Name,
        SourceCode:       req.SourceCode,
        SourceFiles:      req.SourceFiles,
        ABI:              matchedContract.ABI,
        Optimization:     req.Optimization,
        OptimizationRuns: req.OptimizationRuns,
        EVMVersion:       req.EVMVersion,
        ConstructorArgs:  req.ConstructorArgs,
        Libraries:        req.Libraries,
    }

    if err := s.storage.UpdateVerification(ctx, req.Address, verification); err != nil {
        return nil, fmt.Errorf("failed to store verification: %w", err)
    }

    return &VerifyResult{
        Success:      true,
        Address:      req.Address,
        ContractName: matchedContract.Name,
        ABI:          matchedContract.ABI,
        BytecodeHash: matchedContract.BytecodeHash,
        SourceCode:   req.SourceCode,
    }, nil
}

func (s *Service) compile(ctx context.Context, req *VerifyRequest) (*CompilationResult, error) {
    // Get compiler binary
    compiler, err := s.compilerCache.Get(req.CompilerType, req.CompilerVersion)
    if err != nil {
        return nil, err
    }

    // Build input JSON
    input := s.buildCompilerInput(req)
    inputJSON, _ := json.Marshal(input)

    // Run compiler
    cmd := exec.CommandContext(ctx, compiler, "--standard-json")
    cmd.Stdin = bytes.NewReader(inputJSON)

    output, err := cmd.Output()
    if err != nil {
        return nil, fmt.Errorf("compiler execution failed: %w", err)
    }

    // Parse output
    var result CompilationResult
    if err := json.Unmarshal(output, &result); err != nil {
        return nil, fmt.Errorf("failed to parse compiler output: %w", err)
    }

    if len(result.Errors) > 0 {
        for _, e := range result.Errors {
            if e.Severity == "error" {
                return nil, fmt.Errorf("compilation error: %s", e.Message)
            }
        }
    }

    return &result, nil
}

func (s *Service) buildCompilerInput(req *VerifyRequest) *SolcInput {
    sources := make(map[string]*SolcSource)

    if req.SourceCode != "" {
        sources["contract.sol"] = &SolcSource{Content: req.SourceCode}
    }
    for name, content := range req.SourceFiles {
        sources[name] = &SolcSource{Content: content}
    }

    return &SolcInput{
        Language: "Solidity",
        Sources:  sources,
        Settings: &SolcSettings{
            Optimizer: &SolcOptimizer{
                Enabled: req.Optimization,
                Runs:    req.OptimizationRuns,
            },
            EVMVersion: req.EVMVersion,
            OutputSelection: map[string]map[string][]string{
                "*": {
                    "*": {"abi", "evm.bytecode", "evm.deployedBytecode", "metadata"},
                },
            },
            Libraries: req.Libraries,
        },
    }
}

func (s *Service) bytecodeMatches(deployed, compiled, constructorArgs string) bool {
    // Remove metadata hash suffix (CBOR-encoded)
    // Solidity appends ipfs/swarm hash to bytecode
    deployedClean := s.stripMetadata(deployed)
    compiledClean := s.stripMetadata(compiled)

    // Compiled bytecode = creation bytecode + constructor args
    // Deployed bytecode = just the runtime portion
    return deployedClean == compiledClean
}

func (s *Service) stripMetadata(bytecode string) string {
    // Metadata length is encoded in last 2 bytes
    if len(bytecode) < 4 {
        return bytecode
    }

    // Try to find CBOR prefix (0xa2 or 0xa1)
    for i := len(bytecode) - 4; i > len(bytecode)-100; i -= 2 {
        if bytecode[i:i+2] == "a2" || bytecode[i:i+2] == "a1" {
            return bytecode[:i]
        }
    }

    return bytecode
}

// Sourcify integration
func (s *Service) VerifyViaSourcify(ctx context.Context, chainID uint64, address string) (*VerifyResult, error) {
    // Check if already verified on Sourcify
    result, err := s.sourcify.Check(ctx, chainID, address)
    if err != nil {
        return nil, err
    }

    if result.Status == "full" || result.Status == "partial" {
        // Fetch source and store
        source, err := s.sourcify.GetSource(ctx, chainID, address)
        if err != nil {
            return nil, err
        }

        verification := &types.ContractVerification{
            ChainID:         chainID,
            Address:         address,
            CompilerType:    "solidity",
            CompilerVersion: source.CompilerVersion,
            ContractName:    source.ContractName,
            SourceFiles:     source.Sources,
            ABI:             source.ABI,
            VerifiedBy:      "sourcify",
        }

        if err := s.storage.UpdateVerification(ctx, address, verification); err != nil {
            return nil, err
        }

        return &VerifyResult{
            Success:      true,
            Address:      address,
            ContractName: source.ContractName,
            ABI:          source.ABI,
            Message:      "Verified via Sourcify",
        }, nil
    }

    return &VerifyResult{
        Success: false,
        Message: "Contract not found on Sourcify",
    }, nil
}

// Compiler cache
type CompilerCache struct {
    cacheDir string
    mu       sync.RWMutex
    versions map[string]string // version -> binary path
}

func (c *CompilerCache) Get(compilerType, version string) (string, error) {
    c.mu.RLock()
    if path, ok := c.versions[version]; ok {
        c.mu.RUnlock()
        return path, nil
    }
    c.mu.RUnlock()

    c.mu.Lock()
    defer c.mu.Unlock()

    // Double-check after acquiring write lock
    if path, ok := c.versions[version]; ok {
        return path, nil
    }

    // Download compiler
    path, err := c.download(compilerType, version)
    if err != nil {
        return "", err
    }

    c.versions[version] = path
    return path, nil
}

func (c *CompilerCache) download(compilerType, version string) (string, error) {
    // Download from GitHub releases or solc-bin
    var url string
    switch compilerType {
    case "solidity":
        url = fmt.Sprintf("https://github.com/ethereum/solidity/releases/download/v%s/solc-static-linux", version)
    case "vyper":
        url = fmt.Sprintf("https://github.com/vyperlang/vyper/releases/download/v%s/vyper.%s.linux", version, version)
    }

    path := filepath.Join(c.cacheDir, compilerType, version)

    // Download and make executable
    resp, err := http.Get(url)
    if err != nil {
        return "", err
    }
    defer resp.Body.Close()

    os.MkdirAll(filepath.Dir(path), 0755)
    f, err := os.Create(path)
    if err != nil {
        return "", err
    }
    io.Copy(f, resp.Body)
    f.Close()

    os.Chmod(path, 0755)

    return path, nil
}
```

---

## 8. Deployment Architecture

### Docker Compose (Development)

```yaml
# docker/compose.yml

version: '3.8'

services:
  # PostgreSQL
  postgres:
    image: postgres:16
    container_name: indexer-postgres
    environment:
      POSTGRES_DB: indexer
      POSTGRES_USER: indexer
      POSTGRES_PASSWORD: indexer
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./migrations:/docker-entrypoint-initdb.d
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U indexer"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Redis
  redis:
    image: redis:7-alpine
    container_name: indexer-redis
    command: redis-server --appendonly yes
    volumes:
      - redis-data:/data
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Indexer (block processing)
  indexer:
    build:
      context: ..
      dockerfile: docker/Dockerfile.indexer
    container_name: indexer-indexer
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      DATABASE_URL: postgres://indexer:indexer@postgres:5432/indexer?sslmode=disable
      REDIS_URL: redis://redis:6379
      RPC_ENDPOINTS: http://host.docker.internal:9650/ext/bc/C/rpc
      CHAIN_ID: 96369
      LOG_LEVEL: info
      ENABLE_TRACES: "true"
      ENABLE_TOKEN_TRACKING: "true"
      BATCH_SIZE: 100
      WORKERS: 32
    restart: unless-stopped

  # API server
  api:
    build:
      context: ..
      dockerfile: docker/Dockerfile.api
    container_name: indexer-api
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      DATABASE_URL: postgres://indexer:indexer@postgres:5432/indexer?sslmode=disable
      REDIS_URL: redis://redis:6379
      PORT: 8080
      LOG_LEVEL: info
      CORS_ORIGINS: "*"
      RATE_LIMIT: 100
    ports:
      - "8080:8080"
    restart: unless-stopped
    deploy:
      replicas: 2

  # Metrics
  prometheus:
    image: prom/prometheus:v2.47.0
    container_name: indexer-prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.enable-lifecycle'

  # Grafana
  grafana:
    image: grafana/grafana:10.2.0
    container_name: indexer-grafana
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ./grafana/datasources:/etc/grafana/provisioning/datasources
    ports:
      - "3001:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
      GF_USERS_ALLOW_SIGN_UP: "false"

volumes:
  postgres-data:
  redis-data:
  prometheus-data:
  grafana-data:
```

### Kubernetes (Production)

```yaml
# k8s/deployment.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: indexer-api
  namespace: lux-indexer
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 2
  selector:
    matchLabels:
      app: indexer-api
  template:
    metadata:
      labels:
        app: indexer-api
    spec:
      containers:
      - name: api
        image: ghcr.io/luxfi/indexer-api:latest
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: indexer-secrets
              key: database-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: indexer-secrets
              key: redis-url
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "2000m"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: indexer-api
              topologyKey: kubernetes.io/hostname

---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: indexer-pipeline
  namespace: lux-indexer
spec:
  serviceName: indexer-pipeline
  replicas: 1  # Single instance per chain
  selector:
    matchLabels:
      app: indexer-pipeline
  template:
    metadata:
      labels:
        app: indexer-pipeline
    spec:
      containers:
      - name: indexer
        image: ghcr.io/luxfi/indexer:latest
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: indexer-secrets
              key: database-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: indexer-secrets
              key: redis-url
        - name: RPC_ENDPOINTS
          value: "http://node-0:9650/ext/bc/C/rpc,http://node-1:9650/ext/bc/C/rpc"
        - name: CHAIN_ID
          value: "96369"
        resources:
          requests:
            memory: "4Gi"
            cpu: "2000m"
          limits:
            memory: "16Gi"
            cpu: "8000m"
        volumeMounts:
        - name: checkpoint
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: checkpoint
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: fast-ssd
      resources:
        requests:
          storage: 10Gi

---
apiVersion: v1
kind: Service
metadata:
  name: indexer-api
  namespace: lux-indexer
spec:
  selector:
    app: indexer-api
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: indexer-ingress
  namespace: lux-indexer
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - api.explorer.lux.network
    secretName: indexer-tls
  rules:
  - host: api.explorer.lux.network
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: indexer-api
            port:
              number: 80
```

---

## 9. Performance Benchmarks

### Target Performance

| Metric | Target | Current Blockscout |
|--------|--------|-------------------|
| **Block Indexing Rate** | 10,000 blocks/sec | ~100 blocks/sec |
| **API Latency (p50)** | <10ms | ~50ms |
| **API Latency (p99)** | <100ms | ~500ms |
| **API Throughput** | 50,000 req/sec | ~5,000 req/sec |
| **WebSocket Connections** | 100,000 | ~10,000 |
| **Memory Usage (API)** | <512MB | ~2GB |
| **Memory Usage (Indexer)** | <4GB | ~8GB |

### Optimization Strategies

#### Database

1. **Table Partitioning**: Partition by chain_id and block range
2. **Bulk Inserts**: PostgreSQL COPY for batch writes
3. **Read Replicas**: Separate read/write workloads
4. **Connection Pooling**: PgBouncer with 1000 connections
5. **Indexes**: Covering indexes for common queries
6. **BRIN Indexes**: For block_number columns (ordered data)

#### Caching

1. **Block Cache**: LRU cache for recent 10,000 blocks
2. **Transaction Cache**: LRU cache for hot transactions
3. **Balance Cache**: Redis cache with 60s TTL
4. **Query Result Cache**: Redis with query hash key
5. **ABI Cache**: In-memory cache for verified contracts

#### API

1. **Response Compression**: gzip for responses >1KB
2. **Connection Keep-Alive**: HTTP/2 multiplexing
3. **DataLoader**: Batch database queries (N+1 prevention)
4. **Cursor Pagination**: Avoid OFFSET for large datasets
5. **Rate Limiting**: Token bucket with Redis backend

#### Pipeline

1. **Parallel Fetching**: 32 concurrent RPC workers
2. **Batch Processing**: 100 blocks per batch
3. **Channel Buffering**: 10,000 block buffer
4. **Zero-Copy**: Minimize allocations in hot paths
5. **Goroutine Pooling**: Reuse goroutines for processing

---

## 10. Migration Strategy

### From Blockscout

```
Phase 1: Parallel Operation (Week 1-2)
├── Deploy indexer alongside Blockscout
├── Index from genesis in background
├── Route read traffic to both, compare results
└── Monitor performance metrics

Phase 2: Shadow Mode (Week 3)
├── Route all reads to new indexer
├── Blockscout continues indexing (backup)
├── Validate API compatibility
└── Fix any discrepancies

Phase 3: Cutover (Week 4)
├── Point DNS to new indexer
├── Decommission Blockscout
├── Archive Blockscout database
└── Monitor for 48 hours

Phase 4: Optimization (Week 5+)
├── Enable additional features
├── Tune performance
├── Add chain-specific features
└── Documentation
```

### Data Migration

```sql
-- Export from Blockscout (if reusing data)
COPY (SELECT * FROM blocks WHERE number > 0) TO '/tmp/blocks.csv' CSV;
COPY (SELECT * FROM transactions) TO '/tmp/transactions.csv' CSV;
COPY (SELECT * FROM logs) TO '/tmp/logs.csv' CSV;

-- Import to new indexer
COPY blocks FROM '/tmp/blocks.csv' CSV;
COPY transactions FROM '/tmp/transactions.csv' CSV;
COPY logs FROM '/tmp/logs.csv' CSV;

-- Update sequences
SELECT setval('blocks_id_seq', (SELECT MAX(id) FROM blocks));
SELECT setval('transactions_id_seq', (SELECT MAX(id) FROM transactions));
SELECT setval('logs_id_seq', (SELECT MAX(id) FROM logs));
```

---

## Appendix A: API Compatibility Matrix

### Etherscan API Endpoints

| Endpoint | Module | Status |
|----------|--------|--------|
| `/api?module=account&action=balance` | Account | Implemented |
| `/api?module=account&action=balancemulti` | Account | Implemented |
| `/api?module=account&action=txlist` | Account | Implemented |
| `/api?module=account&action=txlistinternal` | Account | Implemented |
| `/api?module=account&action=tokentx` | Account | Implemented |
| `/api?module=account&action=tokennfttx` | Account | Implemented |
| `/api?module=account&action=token1155tx` | Account | Implemented |
| `/api?module=account&action=getminedblocks` | Account | Implemented |
| `/api?module=contract&action=getabi` | Contract | Implemented |
| `/api?module=contract&action=getsourcecode` | Contract | Implemented |
| `/api?module=contract&action=verifysourcecode` | Contract | Implemented |
| `/api?module=transaction&action=gettxreceiptstatus` | Transaction | Implemented |
| `/api?module=transaction&action=getstatus` | Transaction | Implemented |
| `/api?module=block&action=getblockreward` | Block | Implemented |
| `/api?module=block&action=getblockcountdown` | Block | Implemented |
| `/api?module=block&action=getblocknobytime` | Block | Implemented |
| `/api?module=logs&action=getLogs` | Logs | Implemented |
| `/api?module=token&action=tokeninfo` | Token | Implemented |
| `/api?module=token&action=tokenholderlist` | Token | Implemented |
| `/api?module=stats&action=ethsupply` | Stats | Implemented |
| `/api?module=stats&action=ethprice` | Stats | Implemented |
| `/api?module=proxy&action=eth_*` | Proxy | Implemented |

### Blockscout API Endpoints

| Endpoint | Status |
|----------|--------|
| `/api/v2/addresses/{hash}` | Implemented |
| `/api/v2/addresses/{hash}/transactions` | Implemented |
| `/api/v2/addresses/{hash}/token-transfers` | Implemented |
| `/api/v2/addresses/{hash}/tokens` | Implemented |
| `/api/v2/blocks` | Implemented |
| `/api/v2/blocks/{number}` | Implemented |
| `/api/v2/transactions` | Implemented |
| `/api/v2/transactions/{hash}` | Implemented |
| `/api/v2/tokens` | Implemented |
| `/api/v2/tokens/{address}` | Implemented |
| `/api/v2/smart-contracts/{address}` | Implemented |
| `/api/v2/stats` | Implemented |

---

## Appendix B: Metrics

### Prometheus Metrics

```
# Indexer metrics
indexer_blocks_processed_total{chain_id}
indexer_blocks_per_second{chain_id}
indexer_transactions_processed_total{chain_id}
indexer_logs_processed_total{chain_id}
indexer_reorgs_detected_total{chain_id}
indexer_checkpoint_block{chain_id}
indexer_backfill_progress{chain_id}
indexer_pipeline_buffer_size{chain_id}
indexer_write_batch_size{chain_id}
indexer_write_batch_latency_seconds{chain_id}

# API metrics
api_requests_total{method,path,status}
api_request_duration_seconds{method,path}
api_response_size_bytes{method,path}
api_active_connections{}
api_websocket_connections{}
api_websocket_messages_total{direction}

# Cache metrics
cache_hits_total{cache}
cache_misses_total{cache}
cache_hit_ratio{cache}
cache_size_bytes{cache}

# Database metrics
db_connections_active{}
db_connections_idle{}
db_query_duration_seconds{query}
db_rows_affected{operation}
```

---

**Document History**:
- 2025-12-25: Initial architecture design
- Target Completion: Q1 2026

**Authors**:
- Architecture Team, Lux Industries

**Related Documents**:
- LP-3001: Lux Indexer Specification
- LP-3002: Multi-Chain Indexing Strategy
- LP-3003: API Gateway Design
