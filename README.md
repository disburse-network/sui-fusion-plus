# Sui Fusion Plus

A cross-chain atomic swap protocol for Sui blockchain, adapted from the Aptos Fusion Plus project.

## Overview

Sui Fusion Plus implements a cross-chain atomic swap protocol that enables secure asset exchanges between different blockchain networks. The protocol uses hashlock and timelock mechanisms to ensure atomicity and security.

## Architecture

The project consists of several core modules:

### Core Modules

- **`constants`**: Configuration constants and timelock parameters
- **`hashlock`**: Hash-based locking mechanism for atomic swaps
- **`timelock`**: Time-based phase control for escrow lifecycle
- **`resolver_registry`**: Management of authorized resolvers
- **`fusion_order`**: User order creation and Dutch auction logic
- **`escrow`**: Cross-chain asset escrow with atomic swap guarantees

### Cross-Chain Flow

1. **Order Creation**: Users create fusion orders with source assets and destination requirements
2. **Resolver Acceptance**: Authorized resolvers accept orders and create source chain escrows
3. **Destination Escrow**: Resolvers create matching destination chain escrows
4. **Atomic Swap**: Assets are exchanged atomically using hashlock verification
5. **Completion**: Both chains complete the swap or allow recovery

## Key Features

- **Atomic Swaps**: Ensures both chains either complete the swap or allow recovery
- **Dutch Auctions**: Dynamic pricing mechanism for order matching
- **Timelock Phases**: Time-based access control for different phases
- **Hashlock Security**: Cryptographic protection using secret verification
- **Resolver Network**: Managed network of authorized cross-chain operators

## Usage

### Building

```bash
sui move build
```

### Testing

```bash
sui move test
```

### Deployment

```bash
sui client publish --gas-budget 10000000
```

## Cross-Chain Coordination

The protocol requires resolvers to monitor events on both chains:

- `FusionOrderCreatedEvent`: New orders available for acceptance
- `EscrowCreatedEvent`: Escrow creation on source/destination chains
- `EscrowWithdrawnEvent`: Successful withdrawal triggering cross-chain coordination
- `EscrowRecoveredEvent`: Recovery events requiring cleanup

## Security Considerations

- Only registered resolvers can participate in cross-chain swaps
- Timelock phases prevent premature access to escrowed assets
- Hashlock verification ensures only correct secret holders can withdraw
- Safety deposits provide economic incentives for proper behavior

## License

This project is adapted from the Aptos Fusion Plus implementation for Sui blockchain. 