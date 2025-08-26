# 🗳️ ZKVote - Anonymous Voting Protocol

## 🚀 Overview

ZKVote is a **zero-knowledge based privacy voting system** built on the Stacks blockchain using Clarity smart contracts. It enables completely anonymous voting while maintaining verifiability and preventing double-voting through cryptographic commitments and nullifiers.

## ✨ Features

- 🔒 **Anonymous Voting**: Zero-knowledge proofs ensure voter privacy
- 🛡️ **Double-Vote Prevention**: Nullifier system prevents duplicate votes
- 📊 **Real-time Results**: Live vote counting with transparent results
- ⏰ **Time-bound Polls**: Configurable voting periods
- 🔐 **Commitment Scheme**: Two-phase voting with commit-reveal pattern
- ✅ **Cryptographic Verification**: ZK-proof validation for vote integrity

## 🏗️ Architecture

### Core Components

1. **Poll Management**: Create and manage voting polls
2. **Commitment Phase**: Voters commit to their votes using cryptographic hashes
3. **ZK Voting Phase**: Submit anonymous votes with zero-knowledge proofs
4. **Nullifier System**: Prevent double-voting without revealing voter identity
5. **Result Aggregation**: Transparent vote counting and results

## 🛠️ Usage

### Creating a Poll

```clarity
(contract-call? .ZKVote create-poll 
  "Should we implement feature X?" 
  "Vote on whether to prioritize feature X in the next release"
  (list "Yes" "No" "Abstain")
  u1000) ;; Duration in blocks
```

### Committing to Vote

```clarity
(contract-call? .ZKVote commit-vote 
  u1 ;; poll-id
  0x1234567890abcdef...) ;; commitment hash
```

### Submitting Anonymous Vote

```clarity
(contract-call? .ZKVote submit-zk-vote
  u1 ;; poll-id
  0xabcdef1234567890... ;; nullifier hash
  u0 ;; vote option (0 = "Yes")
  0xfedcba0987654321...) ;; zk-proof hash
```

### Viewing Results

```clarity
(contract-call? .ZKVote get-poll-results u1)
```

## 📋 Functions Reference

### Public Functions

| Function | Description |
|----------|-------------|
| `create-poll` | 📝 Create a new voting poll |
| `commit-vote` | 🔐 Commit to a vote choice |
| `submit-zk-vote` | 🗳️ Submit anonymous vote with ZK proof |
| `end-poll` | ⏹️ End an active poll (creator/owner only) |
| `verify-zk-proof` | ✅ Verify zero-knowledge proof |

### Read-Only Functions

| Function | Description |
|----------|-------------|
| `get-poll` | 📊 Get poll information |
| `get-poll-results` | 📈 Get voting results |
| `get-commitment` | 🔍 Check commitment details |
| `has-nullifier-been-used` | 🚫 Check if nullifier was used |
| `is-poll-active` | ⏰ Check if poll is currently active |

## 🔧 Development Setup

### Prerequisites

- Clarinet CLI installed
- Stacks wallet for testing

### Installation

```bash
git clone <repository-url>
cd zkvote
clarinet check
```

### Testing

```bash
clarinet test
```

### Deployment

```bash
clarinet deploy --testnet
```

## 🔐 Security Features

- **Zero-Knowledge Privacy**: Votes are anonymous through ZK proofs
- **Nullifier Protection**: Prevents double-voting without identity exposure  
- **Commitment Binding**: Cryptographic commitments ensure vote integrity
- **Time-bound Security**: Polls have defined start/end periods
- **Access Control**: Poll creators can manage their polls

## 🎯 Use Cases

- 🏛️ **DAO Governance**: Anonymous governance voting
- 🏢 **Corporate Decisions**: Private employee voting
- 🎓 **Academic Surveys**: Anonymous student feedback
- 🌐 **Community Polls**: Privacy-preserving community decisions
- 🗳️ **Elections**: Secure anonymous elections

## 🚧 Limitations (MVP)

- Simplified ZK proof verification (production would need full ZK-SNARK implementation)
- Basic nullifier system (can be enhanced with more sophisticated cryptography)
- Limited to 10 options per poll
- No vote delegation features

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License.

## 🔗 Links

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarity Language Reference](https://docs.stacks.co/clarity/)
- [Zero-Knowledge Proofs](https://en.wikipedia.org/wiki/Zero-knowledge_proof)
```


