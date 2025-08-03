# Sui Fusion Plus Deployment Guide

## Prerequisites

1. **Sui CLI Installation**
   ```bash
   # Install Sui CLI
   curl -fsSL https://raw.githubusercontent.com/MystenLabs/sui/main/docs/scripts/install-sui.sh | sh
   ```

2. **Sui Client Setup**
   ```bash
   # Initialize Sui client
   sui client init
   
   # Add testnet environment
   sui client new-env --alias testnet --rpc https://fullnode.testnet.sui.io:443
   
   # Switch to testnet
   sui client switch --env testnet
   ```

3. **Get Testnet SUI**
   - Visit the [Sui Testnet Faucet](https://discord.gg/sui)
   - Request testnet SUI tokens for your address

## Deployment Steps

### Step 1: Build the Package
```bash
# Ensure you're in the sui-fusion-plus directory
cd sui-fusion-plus

# Build the package
sui move build
```

### Step 2: Deploy to Testnet
```bash
# Deploy the package to testnet
sui client publish --gas-budget 100000000
```

### Step 3: Verify Deployment
```bash
# Check the deployed package
sui client object <PACKAGE_ID>

# List all objects owned by your address
sui client objects
```

## Contract Addresses

After deployment, you'll get the following addresses:
- **Package ID**: The main package containing all modules
- **Resolver Registry**: The global resolver registry object
- **Constants**: The constants module (shared object)

## Testing the Deployment

### 1. Create a Fusion Order
```bash
# Call the new function to create a fusion order
sui client call \
  --package <PACKAGE_ID> \
  --module fusion_order \
  --function new \
  --args <AMOUNT> <DESTINATION_ASSET> <DESTINATION_AMOUNT> <DESTINATION_RECIPIENT> <CHAIN_ID> <HASH> <INITIAL_DESTINATION_AMOUNT> <MIN_DESTINATION_AMOUNT> <DECAY_PER_SECOND> \
  --gas-budget 10000000
```

### 2. Register a Resolver
```bash
# Register a resolver
sui client call \
  --package <PACKAGE_ID> \
  --module resolver_registry \
  --function register_resolver \
  --args <RESOLVER_ADDRESS> \
  --gas-budget 10000000
```

### 3. Create an Escrow
```bash
# Create an escrow from a fusion order
sui client call \
  --package <PACKAGE_ID> \
  --module escrow \
  --function new_from_order \
  --args <FUSION_ORDER_ID> <SAFETY_DEPOSIT_COIN> <RESOLVER_REGISTRY_ID> \
  --gas-budget 10000000
```

## Important Notes

1. **Gas Budget**: The deployment requires significant gas. Ensure you have enough testnet SUI.

2. **Object IDs**: After deployment, note down the object IDs for:
   - Package ID
   - Resolver Registry ID
   - Any other shared objects

3. **Testnet Limitations**: 
   - Testnet has rate limits
   - Objects may be cleaned up periodically
   - Use small amounts for testing

4. **Error Handling**: If deployment fails:
   - Check gas budget
   - Ensure sufficient SUI balance
   - Verify network connectivity

## Post-Deployment Verification

1. **Check Package**: Verify all modules are deployed
2. **Test Basic Functions**: Try creating a simple hashlock or timelock
3. **Monitor Events**: Check for any emitted events
4. **Test Integration**: Verify cross-module interactions work

## Troubleshooting

### Common Issues:
1. **Insufficient Gas**: Increase gas budget
2. **Network Issues**: Check RPC endpoint connectivity
3. **Object Not Found**: Verify object IDs are correct
4. **Permission Errors**: Ensure you're using the correct address

### Debug Commands:
```bash
# Check transaction status
sui client tx-block <TRANSACTION_DIGEST>

# View object details
sui client object <OBJECT_ID>

# Check account balance
sui client balance
```

## Next Steps

After successful deployment:
1. Test all core functionality
2. Document the deployed addresses
3. Create integration tests
4. Monitor for any issues
5. Prepare for mainnet deployment 