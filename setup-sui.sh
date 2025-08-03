#!/bin/bash

# Sui Client Setup Script
# This script helps set up the Sui client for deployment

echo "🔧 Setting up Sui client for deployment..."
echo "=========================================="

# Check if Sui CLI is installed
if ! command -v sui &> /dev/null; then
    echo "❌ Sui CLI not found. Please install it first:"
    echo "   curl -fsSL https://raw.githubusercontent.com/MystenLabs/sui/main/docs/scripts/install-sui.sh | sh"
    exit 1
fi

echo "✅ Sui CLI found"

# Initialize Sui client if not already done
if [ ! -f ~/.sui/sui_config/client.yaml ]; then
    echo "🔧 Initializing Sui client..."
    sui client init
else
    echo "✅ Sui client already initialized"
fi

# Add testnet environment
echo "🌐 Adding testnet environment..."
sui client new-env --alias testnet --rpc https://fullnode.testnet.sui.io:443

# Switch to testnet
echo "🔄 Switching to testnet..."
sui client switch --env testnet

# Create new address
echo "🔑 Creating new address..."
sui client new-address ed25519

# Get the active address
ACTIVE_ADDRESS=$(sui client active-address)
echo "✅ Active address: $ACTIVE_ADDRESS"

echo ""
echo "🎉 Sui client setup complete!"
echo "=============================="
echo "📝 Next steps:"
echo "1. Get testnet SUI from the faucet:"
echo "   - Visit: https://discord.gg/sui"
echo "   - Request testnet SUI for address: $ACTIVE_ADDRESS"
echo ""
echo "2. Run the deployment script:"
echo "   ./deploy.sh"
echo ""
echo "3. Or deploy manually:"
echo "   sui client publish --gas-budget 100000000" 