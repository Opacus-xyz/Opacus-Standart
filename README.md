# Opacus ERC Standards — Contracts

Six draft ERC proposals defining the Opacus Protocol on-chain primitives.  
Each standard charges a **1 % protocol fee** to `0xA943F46eE5f977067f07565CF1d31A10B68D7718` (Opacus Treasury).

---

## Standards

| ERC | Name | Emoji | Contract | Proposal |
|-----|------|-------|----------|---------|
| ERC-7750 | Opacus Nitro Agent Execution | ⚡ | [ERC7750OpacusNitro.sol](./ERC7750OpacusNitro.sol) | [EIP-7750.md](./eip/EIP-7750.md) |
| ERC-7751 | H3 Geospatial Agent Routing | 📍 | [ERC7751H3Routing.sol](./ERC7751H3Routing.sol) | [EIP-7751.md](./eip/EIP-7751.md) |
| ERC-7752 | 0G Cross-Chain Bridge Intent | 💾 | [ERC7752ZeroGBridge.sol](./ERC7752ZeroGBridge.sol) | [EIP-7752.md](./eip/EIP-7752.md) |
| ERC-7753 | Proof-Based Escrow V2 | 🔒 | [ERC7753EscrowV2.sol](./ERC7753EscrowV2.sol) | [EIP-7753.md](./eip/EIP-7753.md) |
| ERC-7754 | Cross-Chain Token Mint | 💸 | [ERC7754CrossChainMint.sol](./ERC7754CrossChainMint.sol) | [EIP-7754.md](./eip/EIP-7754.md) |
| ERC-7755 | Kinetic Agent Reputation Score | 🏆 | [ERC7755KineticScore.sol](./ERC7755KineticScore.sol) | [EIP-7755.md](./eip/EIP-7755.md) |

---

## Fee Architecture

All six contracts inherit `lib/OpacusFeeBase.sol`:

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
│   └── IERC7755.sol
├── ERC7750OpacusNitro.sol
├── ERC7751H3Routing.sol
├── ERC7752ZeroGBridge.sol
├── ERC7753EscrowV2.sol
├── ERC7754CrossChainMint.sol
├── ERC7755KineticScore.sol
└── eip/
    ├── EIP-7750.md
    ├── EIP-7751.md
    ├── EIP-7752.md
    ├── EIP-7753.md
    ├── EIP-7754.md
    └── EIP-7755.md
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
```

---

## Submitting EIP Proposals

1. Fork [ethereum/EIPs](https://github.com/ethereum/EIPs).
2. Copy the relevant `eip/EIP-77xx.md` into `EIPS/eip-77xx.md`.
3. Open a PR and post the discussion link at https://ethereum-magicians.org/u/bl10buer/.
