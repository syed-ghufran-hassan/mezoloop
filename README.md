# MezoLoop

**Automated looping & yield vault for MUSD/MEZO on Mezo.**

[![Mezo Buildathon](https://img.shields.io/badge/Mezo%20Buildathon-Track%201-blue)](https://mezo.org)
[![Testnet](https://img.shields.io/badge/Network-Mez%C3%B8%20Testnet-orange)](https://explorer.test.mezo.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

MezoLoop is a DeFi strategy vault built for the **Mezo Buildathon, Track 1**. It integrates **MUSD** and **MEZO** to let users earn automated yield and loop their MEZO positions with MUSD borrowing — all with built-in risk management and oracle safety.

## 🚀 Features

- **MUSD Yield Vault** — Deposit MUSD, earn auto-compounded yield.
- **MEZO Loop Vault** — Deposit MEZO, borrow MUSD, swap, and redeposit to achieve up to 2x leveraged yield.
- **Auto-Deleverage** — Health factor monitoring automatically reduces leverage when liquidation risk rises.
- **Composite Oracle** — Uses Pyth for BTC/MUSD and a TWAP fallback for MEZO, with deviation guards and conservative pricing.
- **Risk Manager** — Centralized risk checks block unsafe borrows during price volatility.
- **Testnet Ready** — Deployed and verified on Mezo Testnet.

## 🧠 Architecture

 ```bash
 flowchart TD
    User[User] --> |Deposit MUSD| MUSDVault[MUSD Yield Vault]
    User --> |Deposit MEZO| MEZOLoop[MEZO Loop Vault]
    
    MUSDVault --> |Supply/Withdraw| Lending[Mezo Lending Adapter]
    MUSDVault --> |Yield| Strategy[Mock Strategy]
    
    MEZOLoop --> |Open/Close Loop| Lending
    MEZOLoop --> |Swap MUSD ↔ MEZO| DEX[Tigris DEX Adapter]
    MEZOLoop --> |Check Health| Risk[Risk Manager]
    
    Risk --> |Get Prices| Oracle[Composite Oracle]
    Oracle --> |BTC/USD, MUSD/USD| Pyth[Pyth Network]
    Oracle --> |MEZO/MUSD TWAP| TWAP[TWAP Oracle]
    TWAP --> |Read Pool| TigrisPool[Tigris MEZO/MUSD Pool]
    
    Lending --> |Borrow/Repay| BorrowerOps[BorrowerOperations]
    Lending --> |Collateral| Collateral[BTC/MEZO]
    DEX --> |Swap| TigrisRouter[Tigris Router]
    
    MUSDVault --> |MUSD| MUSDToken[MUSD Token]
    MEZOLoop --> |MEZO| MEZOToken[MEZO Token]
```  

| Component | Role |
|-----------|------|
| **MUSD Yield Vault** | ERC-4626 vault for MUSD deposits. Auto-compounds yield via a pluggable strategy. |
| **MEZO Loop Vault** | Accepts MEZO, borrows MUSD, swaps, and redeposits to create leveraged yield. Includes auto-deleverage. |
| **Risk Manager** | Centralised health-factor checks. Blocks unsafe borrows during price deviations. Triggers auto-deleverage. |
| **Composite Oracle** | Aggregates Pyth (BTC, MUSD) and a TWAP (MEZO) with staleness checks and conservative pricing. |
| **Pyth Network** | Official price feeds for BTC/USD and MUSD/USD on Mezo Testnet. |
| **TWAP Oracle** | Time-weighted average price for MEZO derived from the Tigris MEZO/MUSD pool. |
| **Mezo Lending Adapter** | Abstracts Mezo's BorrowerOperations for depositing collateral and borrowing/repaying MUSD. |
| **Tigris DEX Adapter** | Wraps Tigris Router for MUSD ↔ MEZO swaps with slippage protection. |
| **BorrowerOperations** | Mezo's native lending contract (Liquity-style trove system). |
| **Tigris Router** | Mezo's native DEX router for token swaps. |

## 📡 Oracle Design

MezoLoop uses a **composite oracle** to safely price assets:

- **BTC/USD** → Pyth Network
- **MUSD/USD** → Pyth Network
- **MEZO/USD** → TWAP from the Tigris MEZO/MUSD pool, multiplied by the Pyth MUSD/USD price.

**Safety features:**
- **Staleness checks** — Pyth prices must be fresher than 60 seconds.
- **Deviation guard** — If the spot price deviates more than 5% from the TWAP, the oracle returns a conservative price (lower for collateral, higher for debt).
- **Fallback hierarchy** — If Pyth is stale, the system falls back to TWAP where applicable.

> ⚠️ **Testnet Disclaimer:** The MEZO price on Mezo Testnet relies on a low-liquidity TWAP from the Tigris MEZO/MUSD pool. This is not manipulation-resistant. For production, a robust oracle solution is required.

## 📍 Deployed Contracts (Mezo Testnet)

| Contract | Address |
|----------|---------|
| Pyth Oracle | `0x2880aB155794e7179c9eE2e38200202908C17B43` |
| MUSD Token | `0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503` |
| Tigris Router | `0x9a1ff7FE3a0F69959A3fBa1F1e5ee18e1A9CD7E9` |
| Tigris PoolFactory | `0x4947243CC818b627A5D06d14C4eCe7398A23Ce1A` |
| BTC/USD Pyth Feed ID | `0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43` |
| MEZO Token | *(Request from Mezo Discord)* |
| BorrowerOperations | *(Request from Mezo Discord)* |

**MezoLoop Contracts:**
- `CompositeOracle`: `0x...`
- `MUSDYieldVault`: `0x...`
- `MEZOLoopVault`: `0x...`
- `RiskManager`: `0x...`

*(Update these addresses after deployment.)*

## 🛠 Tech Stack

- **Smart Contracts:** Solidity ^0.8.20, Foundry, OpenZeppelin
- **Oracles:** Pyth Network, custom TWAP from Tigris V3
- **DEX:** Tigris (Mezo Pools)
- **Frontend:** Next.js, wagmi, viem, RainbowKit *(in progress)*
- **Network:** Mezo Testnet

## 🚦 Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 20+ (for frontend)
- Mezo Testnet added to your wallet

### Installation

```bash
git clone https://github.com/your-username/mezoloop.git
cd mezoloop

forge install OpenZeppelin/openzeppelin-contracts
forge install foundry-rs/forge-std
```

### Environment Setup

```bash
Create a .env file:

PRIVATE_KEY=your_wallet_private_key
MEZO_RPC=https://rpc.test.mezo.org

Load it:

source .env

Test:

forge test -vvv

Deploy:

forge script script/Deploy.s.sol:Deploy \
  --rpc-url $MEZO_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast --legacy

Verify:

forge verify-contract <ADDRESS> src/YourContract.sol:YourContract \
  --chain-id 31611 \
  --verifier-url https://explorer.test.mezo.org/api


```

### Testnet Resources

Mezo Testnet Faucet: https://faucet.test.mezo.org/

Mezo Testnet dApp: https://testnet.mezo.org

Block Explorer: https://explorer.test.mezo.org/

Mezo Discord: https://discord.mezo.org

Wave 1 (Current)
 
- Composite Oracle with Pyth + TWAP fallback
 

- MUSD Yield Vault
 

- MEZO Loop Vault with auto-deleverage
 

- Risk Manager
 

- Frontend UI
 

- Testnet deployment & demo video

Wave 2 (Planned)

 

- Integrate real Mezo BorrowerOperations for lending
 

- Deploy on Base / BNB Chain / Ethereum
 

- Add MUSD/MEZO liquidity pools and DEX integrations
 

- Staking derivatives for MEZO
 

- Strategy marketplace and vault aggregator
 
- Telegram alerts for liquidation risk

🎯 Track 1 Alignment

This project directly addresses the DeFi (Borrowing, Lending, Looping, and Yield) track by:

- Expanding MUSD & MEZO utility as collateral and productive capital.

- Building composable vaults that plug into lending markets and DEXs.

- Extending Mezo's core products (borrowing, yield) rather than building an unrelated app.

- Demonstrating long-term commitment with a clear Wave 2 roadmap.

