# Digital securities ↔ OP_NET — end-to-end wiring

OP_NET (Bitcoin L1 metaprotocol, virtual chain ID `4294967299` / `0x100000003`)
is treated as just another destination chain by the Lux securities stack. No
new processes are needed — every link is a native Lux chain.

```
┌─ EVM L1 (Lux C-Chain, Zoo, … any chain ID) ─────────────────────┐
│                                                                  │
│   SecurityToken (T-REX) ◄── identityRegistry ──► IIdentityRegistry
│        │                                              │          │
│        │ AGENT_ROLE                                   │          │
│        ▼                                              ▼          │
│   SecuritiesGateway.outbound(token, amount, destChain, recipient)│
│        │                                                         │
│        │ emit Outbound(destChain, nonce, token, sender,           │
│        │               recipient, amount)                         │
└────────┼─────────────────────────────────────────────────────────┘
         │
         ▼
┌─ R-Chain  (luxfi/node — chains/relayvm) ──────────────────────────┐
│                                                                    │
│   Channel(EVM_L1 ↔ OPNET)         <- pre-opened by governor       │
│   SendMessage(channel, payload, proof_of_burn)                     │
│   ReceiveMessage(channel, ...)                                     │
│                                                                    │
└────────┼───────────────────────────────────────────────────────────┘
         │
         ▼
┌─ O-Chain  (luxfi/node — chains/oraclevm) ────────────────────────┐
│                                                                   │
│   Feed("opnet:btc-tip"):                                          │
│     - sources: [bitcoin RPC, esplora, luxfi/indexer + opnet]      │
│     - operators: N validators                                     │
│     - aggregation: median of confirmations (≥6) + canonical tip   │
│                                                                   │
│   Feed("opnet:burns"):                                            │
│     - watches OP_NET burn-to-bridge address (Taproot)             │
│     - submits Observation(burn-event, claimed evm recipient)      │
│     - aggregated = quorum-signed canonical OP_NET burn proof      │
│                                                                   │
└────────┼──────────────────────────────────────────────────────────┘
         │
         ▼
┌─ MPC (luxfi/mpc) — FROST/Taproot threshold ───────────────────────┐
│                                                                    │
│   Inbound  (OP_NET → EVM): take aggregated burn observation, sign  │
│            an EIP-712-style "INBOUND" message for                  │
│            SecuritiesGateway.inbound(...). The recovered address   │
│            == gateway.mpcGroup, mint succeeds on EVM only if       │
│            IIdentityRegistry.isVerified(recipient).                │
│                                                                    │
│   Outbound (EVM → OP_NET): take R-Chain delivery of an Outbound    │
│            event, build a Bitcoin Taproot inscription that mints   │
│            OP-20 to the recipient pubkey, sign via FROST           │
│            (signing_handler_frost.go), broadcast to BTC.           │
│                                                                    │
└────────┼──────────────────────────────────────────────────────────┘
         │
         ▼
       Bitcoin L1 (OP_NET indexer accepts the inscription, OP-20 minted)
```

## Component map

| Layer | Repo | Path | What it provides |
|---|---|---|---|
| EVM bridge | `@luxfi/contracts` | `securities/bridge/SecuritiesGateway.sol` | `outbound(...)`, MPC-signed `inbound(...)` |
| EVM securities | `@luxfi/contracts` | `securities/token/SecurityToken.sol` | T-REX `IToken`, `mint` checks `IIdentityRegistry.isVerified` |
| Cross-chain message bus | `luxfi/node` | `chains/relayvm` | Channel + SendMessage + GetVerifiedMessage |
| External-data oracle | `luxfi/node` | `chains/oraclevm` | Feed + Observation + Aggregation + ZK proof |
| Threshold signer | `luxfi/mpc` | `pkg/eventconsumer/signing_handler_frost.go` | FROST/Taproot/EdDSA signing |
| Settlement intent tracker | `luxfi/mpc` | `pkg/settlement/intent.go` | Generic chain-agnostic intent, on-chain receipt verification |
| Securities indexing | `luxfi/graph` | `indexer/indexer_securities.go`, `resolvers/securities/` | Full ERC-3643 + ONCHAINID event ingestion + GraphQL |
| Generic block explorer | `luxfi/indexer` | `multichain/manager.go` | Protocol consts: `erc3643`, `onchainid`, `opnet` |
| OP_NET locale registration | `@luxfi/contracts` | `script/RegisterOPNET.s.sol` | Adds OP_NET (chain `4294967299`) to TeleportProposalBridge |
| OP_NET yield strategy | `@luxfi/contracts` | `bridge/yield/strategies/OPNETStrategy.sol` | Wraps Babylon BTC staking for bridged LBTC on Lux |
| OP_NET conformance tests | `@luxfi/contracts` | `test/teleport/OPNET{Conformance,Outbound}.t.sol` | 36 + 2 tests |
| Securities ↔ OP_NET tests | `@luxfi/contracts` | `test/securities/SecuritiesGateway.t.sol` | 7 tests, full round-trip |

## Operator wiring (one-time per network)

```bash
# 1. Open R-Chain channels (Lux↔OP_NET, Zoo↔OP_NET, …)
luxd rpc relay openChannel \
  --source <luxChainID> --dest 4294967299 \
  --ordering ordered --version 1.0

# 2. Register OP_NET feeds on O-Chain
luxd rpc oracle registerFeed \
  --name opnet:btc-tip \
  --sources "https://blockstream.info/api,https://opnet.org/api" \
  --operators "<opNodeID1>,<opNodeID2>,<opNodeID3>" \
  --updateFreq 30s --policy "median,confirmations≥6"

luxd rpc oracle registerFeed \
  --name opnet:burns \
  --sources "https://opnet.org/api/burns?address=<gatewayBtcAddr>" \
  --operators "<opNodeID1>,<opNodeID2>,<opNodeID3>" \
  --updateFreq 60s --policy "quorum-2-of-3"

# 3. Register MPC FROST policy for OP_NET destinations
mpcctl policy add \
  --kind frost-taproot \
  --chain opnet \
  --threshold 3 \
  --total 5

# 4. Register OP_NET locale on the EVM bridge surface
forge script script/RegisterOPNET.s.sol --broadcast \
  -e TELEPORT_BRIDGE=0x... -e LBTC_TOKEN=0x... -e MPC_SIGNER=0x...

# 5. Wire SecuritiesGateway
forge script <wire>.s.sol --broadcast
# - SecuritiesGateway.registerToken(securityToken)
# - SecurityToken.grantRole(AGENT_ROLE, address(gateway))
```

## Why no separate "relayer process"

Lux ships the relayer as a chain (R-Chain / `relayvm`) and the oracle as a
chain (O-Chain / `oraclevm`). Validators run them as part of the standard
consensus set. There's no Go binary to deploy separately — operators just
run validators that observe Bitcoin/OP_NET (for O-Chain feeds) and forward
verified messages (for R-Chain channels). MPC FROST signing is a sidecar to
the validator.

## Observability

Everything is queryable from `@luxfi/graph` once the gateway is deployed:

```graphql
query {
  securityTransfers(token: "0x...") { from to value txHash }
  transferAgentActions(kind: "AddressFrozen") { user owner blockNumber }
  onchainIdClaims(identity: "0x...") { topic issuer claimId }
  identityRegistryActions(kind: "IdentityRegistered") { topic1 topic2 }
}
```

For the OP_NET cross-chain leg, query R-Chain via the `relay` resolver and
O-Chain via the `oracle` resolver.
