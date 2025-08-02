#!/bin/bash

echo "🔧 Setting up Sui client for deployment..."

# Function to handle interactive prompts
setup_sui_client() {
    echo "Setting up Sui client configuration..."
    
    # Create the config directory
    mkdir -p ~/.sui/sui_config
    
    # Initialize with testnet environment
    echo "y" | sui client new-env --alias testnet --rpc https://fullnode.testnet.sui.io:443 2>/dev/null || true
    
    # Create a new address
    echo "Creating new address..."
    sui client new-address ed25519 2>/dev/null || {
        echo "Failed to create address automatically. Please run manually:"
        echo "sui client new-address ed25519"
        return 1
    }
    
    echo "✅ Sui client setup complete!"
}

# Run the setup
setup_sui_client

if [ $? -eq 0 ]; then
    echo ""
    echo "🎯 Next steps:"
    echo "1. Get testnet coins: sui client faucet"
    echo "2. Deploy: sui client publish --gas-budget 100000000"
    echo "3. Update DEPLOYMENT_TRACKING.md with the new address"
else
    echo ""
    echo "⚠️  Manual setup required:"
    echo "1. Run: sui client new-address ed25519"
    echo "2. Run: sui client faucet"
    echo "3. Run: sui client publish --gas-budget 100000000"
fi 