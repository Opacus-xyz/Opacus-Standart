# Opacus ERC Standards — Contracts

Seven draft ERC proposals defining the Opacus Protocol on-chain primitives.  
Each standard charges a **1 % protocol fee** to `0xA943F46eE5f977067f07565CF1d31A10B68D7718` (Opacus Treasury).

---

## Standard Components

All Opacus standards share four cross-cutting architectural primitives:

### 1. DID Mapping
Every agent is assigned a **Decentralised Identifier (DID)** deterministically derived from their wallet address and H3 geospatial cell:

```
did:opacus:h3:<h3Index>:<wallet>
  └── computed as keccak256(abi.encodePacked(h3Index, walletAddress))
```

This links `wallet_address` to `H3_index` in a one-to-one, collision-free mapping that is fully reproducible off-chain and verifiable on-chain via ERC-7751.

### 2. Signature Challenge
Off-chain authentication uses a **unified nonce-based challenge protocol** with a **5-minute TTL**:

```
Challenge:  keccak256(wallet || nonce || timestamp)
Message:    "Opacus Auth: <challenge> expires <timestamp+300>"
Signature:  EIP-191 personal_sign (EVM) / ed25519 (Solana)
```

Nonces are single-use and server-side invalidated on first use. Any request with `timestamp + 300 < block.timestamp` MUST be rejected.

### 3. Revenue Distribution
**1 % Automated On-chain Protocol Fee** is collected on every value-bearing transaction across all standards and forwarded atomically to the Opacus Treasury:

```
OPACUS_TREASURY = 0xA943F46eE5f977067f07565CF1d31A10B68D7718
FEE_BPS         = 100   (1 % of gross amount)
```

ETH and ERC-20 tokens are both supported. The fee is non-refundable; the remaining 99 % is held as a recoverable bond or forwarded to the counterparty.

### 4. Transport Layer
All agent-to-agent communication MUST use the standardised **`X-Opacus-QUIC` HTTP/3 header** for transport negotiation:

```
X-Opacus-QUIC: mode=<standard|kernel-bypass|datagram>; zero-rtt=<0|1>; latency-us=<us>
```

Transport endpoint registration is governed by **ERC-7756**. Kernel-bypass mode (eBPF/XDP) achieves sub-20 µs end-to-end latency for MEV and time-critical agent tasks.

---

## Standards

| ERC | Name | Emoji | Contract | Proposal |
|-----|------|-------|----------|---------|
| ERC-7750 | Opacus Nitro Agent Execution | ⚡ | [ERC7750OpacusNitro.sol](./ERC7750OpacusNitro.sol) | [EIP-7750.md](./eip/EIP-7750.md) |
| ERC-7751 | H3 Geospatial Agent Routing | 📍 | [ERC7751H3Routing.sol](./ERC7751H3Routing.sol) | [EIP-7751.md](./eip/EIP-7751.md) |
| ERC-7752 | 0G Cross-Chain Bridge Intent | 💾 | [ERC7752ZeroGBridge.sol](./ERC7752ZeroGBridge.sol) | [EIP-7752.md](./eip/EIP-7752.md) |
| ERC-7753 | Proof-Based Escrow V2 | 🔒 | [ERC7753EscrowV2.sol](./contracts/ERC7753EscrowV2.sol) | [EIP-7753.md](./eip/EIP-7753.md) |
| ERC-7754 | Cross-Chain Token Mint | 💸 | [ERC7754CrossChainMint.sol](./contracts/ERC7754CrossChainMint.sol) | [EIP-7754.md](./eip/EIP-7754.md) |
| ERC-7755 | Kinetic Agent Reputation Score | 🏆 | [ERC7755KineticScore.sol](./contracts/ERC7755KineticScore.sol) | [EIP-7755.md](./eip/EIP-7755.md) |
| ERC-7756 | QUIC Transport Registry | 🌐 | [ERC7756QuicTransport.sol](./contracts/ERC7756QuicTransport.sol) | [EIP-7756.md](./eip/EIP-7756.md) |

---

## Fee Architecture

All seven contracts inherit `lib/OpacusFeeBase.sol`:

```
gross input
   │
   ├──  1% ──► OPACUS_TREASURY (0xA943...7718)   — instant, atomic
   │
   └── 99% ──► contract escrow                   — released on success,
                                                    refunded on cancel/expiry
```

```solidity
uint256 public constant FEE_BPS       = 100;           // 1%
address public constant OPACUS_TREASURY = 0xA943F46eE5f977067f07565CF1d31A10B68D7718;
```

ETH **and** ERC-20 tokens are both supported in every contract.

---

## Directory Structure

```
contracts/
├── lib/
│   └── OpacusFeeBase.sol         # shared fee + reentrancy base
├── interfaces/
│   ├── IERC7750.sol
│   ├── IERC7751.sol
│   ├── IERC7752.sol
│   ├── IERC7753.sol
│   ├── IERC7754.sol
│   ├── IERC7755.sol
│   └── IERC7756.sol
├── ERC7750OpacusNitro.sol
├── ERC7751H3Routing.sol
├── ERC7752ZeroGBridge.sol
├── ERC7753EscrowV2.sol
├── ERC7754CrossChainMint.sol
├── ERC7755KineticScore.sol
├── ERC7756QuicTransport.sol
└── eip/
    ├── EIP-7750.md
    ├── EIP-7751.md
    ├── EIP-7752.md
    ├── EIP-7753.md
    ├── EIP-7754.md
    ├── EIP-7755.md
    └── EIP-7756.md
```

---

## Quick Start (Hardhat)

```bash
npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox
npx hardhat compile
npx hardhat test
```

Solidity version: `^0.8.24`  
No OpenZeppelin dependency — all helpers are self-contained.

---

## Inter-Contract Relationships

```
ERC-7755 (KineticScore)
     │ kineticScore field
     ▼
ERC-7751 (H3Routing)   ←── discovery layer
     │ agent discovery
     ▼
ERC-7750 (NitroTask)   ←── execution layer
     │ task proofs feed reputation
     ▼
ERC-7755 (score update via oracle)

ERC-7753 (EscrowV2)    ←── settlement layer
     │ escrow success rate
     ▼
ERC-7755 (score update via oracle)

ERC-7752 (0G Bridge) + ERC-7754 (CrossChainMint)
     │ cross-chain value movement
     ▼
ERC-7755 (ogComputeBps score dimension)

ERC-7756 (QUIC Transport)
     │ quicEndpoint field in AgentRecord
     ▼
ERC-7751 (H3Routing) — endpoint is discovered via registry
```

---

## Submitting EIP Proposals

1. Fork [ethereum/EIPs](https://github.com/ethereum/EIPs).
2. Copy the relevant `eip/EIP-77xx.md` into `EIPS/eip-77xx.md`.
3. Rename the file to match the EIP number exactly (e.g. `eip-7756.md`).
4. Open a PR to `ethereum/EIPs` with title `Add EIP-7756: QUIC Transport Registry Standard`.
5. Post the discussion link at https://ethereum-magicians.org/u/bl10buer/ and add the URL to the `discussions-to` frontmatter field.

---

## License

MIT — see [LICENSE](./LICENSE).
