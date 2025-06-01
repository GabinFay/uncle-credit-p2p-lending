# Uncle Credit: P2P Lending Platform with Social Vouching

## 🚀 Live Demo on Flow EVM Testnet

**Try it now:** [Uncle Credit App](https://uncle-credit-p2p-lending.vercel.app) *(Coming soon)*

**Deployed Contracts on Flow EVM Testnet:**
- 🪙 **MockERC20 (TUSDC)**: `0xB09f91f8E16C977186CAf7404BE7650cc4629B00`
- 👥 **UserRegistry**: `0x16B081647deCEfb0a3Cb83e3e69a91e9931De70d`
- ⭐ **Reputation**: `0x20cBdA8c47Db6582aE21182C4D0b995fed2b2A94`
- 🏦 **P2PLending**: `0xe6FE723dBCac89487F1BEC20BA94795B44f3d4A5`

**Explorer Links:**
- [View Contracts on Flow Testnet Explorer](https://evm-testnet.flowscan.io)

## 📋 Overview

Uncle Credit is a revolutionary P2P lending platform that combines traditional lending with social vouching mechanisms. Built on Flow EVM, it enables users to lend and borrow with community trust as collateral.

### 🌟 Key Features

- **P2P Lending**: Direct lending between users with customizable terms
- **Social Vouching**: Community members can vouch for borrowers with stake
- **Reputation System**: Dynamic scoring based on lending/borrowing behavior
- **Real Transactions**: All interactions are on-chain with Flow EVM
- **Modern UI**: Beautiful, production-ready interface built with Next.js + shadcn/ui

## 🛠 Technology Stack

### Smart Contracts
- **Solidity 0.8.20** - Smart contract development
- **Foundry** - Development framework and testing
- **OpenZeppelin** - Security-audited contract libraries

### Frontend
- **Next.js 14** - React framework with App Router
- **TypeScript** - Type safety and developer experience
- **Tailwind CSS** - Utility-first styling
- **shadcn/ui** - Modern component library
- **Wagmi v2** - React hooks for Ethereum
- **RainbowKit** - Wallet connection interface

### Blockchain
- **Flow EVM Testnet** - Fast, developer-friendly EVM-compatible blockchain
- **Chain ID**: 545
- **RPC**: https://testnet.evm.nodes.onflow.org

## 🏗 Architecture

### Smart Contract System

```
UserRegistry.sol     - User registration and identity
    ↓
Reputation.sol       - Reputation scoring and social vouching
    ↓
P2PLending.sol       - Core P2P lending logic
```

### User Flows

1. **Borrower Flow**: Register → Request Loan → Accept Offer → Repay
2. **Lender Flow**: Register → Create Offer → Fund Loans → Receive Repayments
3. **Voucher Flow**: Register → Vouch for Borrowers → Earn/Lose Reputation

## 🚀 Getting Started

### Prerequisites
- Node.js 18+ and yarn
- Git
- MetaMask or compatible wallet

### Installation

```bash
# Clone the repository
git clone https://github.com/GabinFay/uncle-credit-p2p-lending.git
cd uncle-credit-p2p-lending

# Install dependencies
cd packages/nextjs
yarn install

# Set up environment variables
cp .env.example .env.local
# Edit .env.local with your configuration

# Start the development server
yarn dev
```

### Smart Contract Development

```bash
# Navigate to foundry package
cd packages/foundry

# Install dependencies
forge install

# Compile contracts
forge build

# Run tests
forge test

# Deploy to Flow Testnet (requires PRIVATE_KEY in .env)
forge script script/DeployUncleCreditContracts.s.sol:DeployUncleCreditContracts --fork-url https://testnet.evm.nodes.onflow.org --broadcast --legacy --private-key $PRIVATE_KEY
```

## 📖 How It Works

### 1. User Registration
Users register with a display name (World ID integration planned for future)

### 2. Creating Loan Offers (Lenders)
```solidity
function createLoanOffer(
    uint256 amount,
    address token,
    uint16 interestRateBPS,
    uint256 durationSeconds,
    uint256 requiredCollateralAmount,
    address collateralToken
) external returns (bytes32 offerId)
```

### 3. Loan Requests (Borrowers)
```solidity
function createLoanRequest(
    uint256 amount,
    address token,
    uint16 proposedInterestRateBPS,
    uint256 proposedDurationSeconds,
    uint256 offeredCollateralAmount,
    address offeredCollateralToken
) external returns (bytes32 requestId)
```

### 4. Social Vouching
Community members can stake tokens to vouch for borrowers:
```solidity
function addVouch(
    address borrowerToVouchFor,
    uint256 amountToStake,
    address tokenAddress
) external
```

### 5. Reputation System
- **On-time repayments**: +10 points
- **Late repayments**: +3 points  
- **Loan defaults**: -50 points
- **Vouching for defaulters**: -20 points

## 🧪 Testing

The platform includes comprehensive testing:

### Smart Contract Tests
```bash
cd packages/foundry
forge test -vvv
```

### Integration Tests
```bash
cd packages/nextjs
yarn test
```

### Manual Testing Script
A complete workflow demo script is available:
```bash
node scripts/fullWorkflowDemo.js
```

## 🌐 Deployment

### Frontend Deployment (Vercel)
```bash
# Build the frontend
cd packages/nextjs
yarn build

# Deploy to Vercel
vercel --prod
```

### Contract Deployment
Contracts are deployed on Flow EVM Testnet. See addresses above.

## 🔐 Security Considerations

- All contracts inherit from OpenZeppelin's battle-tested libraries
- ReentrancyGuard prevents reentrancy attacks
- SafeERC20 for secure token transfers
- Comprehensive input validation
- Role-based access control

## 🗺 Roadmap

### Phase 1 (Current) ✅
- Core P2P lending functionality
- Social vouching system
- Basic reputation scoring
- Flow EVM deployment

### Phase 2 (Planned)
- World ID integration for Sybil resistance
- Cross-chain reputation with LayerZero
- Advanced loan modification features
- Mobile app development

### Phase 3 (Future)
- Credit scoring AI integration
- Insurance mechanisms
- Governance token and DAO
- Institutional lender onboarding

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built for Flow blockchain hackathons
- Inspired by traditional credit systems and DeFi innovations
- Thanks to the Flow, OpenZeppelin, and scaffold-eth communities

## 📞 Contact

- **GitHub**: [@GabinFay](https://github.com/GabinFay)
- **Project**: [Uncle Credit P2P Lending](https://github.com/GabinFay/uncle-credit-p2p-lending)

---

**Made with ❤️ on Flow EVM**