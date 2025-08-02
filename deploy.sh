#!/bin/bash

echo "🚀 Setting up Sui Fusion Plus deployment..."

# Create Sui config directory if it doesn't exist
mkdir -p ~/.sui/sui_config

# Create a basic client.yaml configuration
cat > ~/.sui/sui_config/client.yaml << 'EOF'
---
accounts: []
active_address: null
active_env: testnet
environments:
  - alias: testnet
    rpc: "https://fullnode.testnet.sui.io:443"
    ws: "wss://fullnode.testnet.sui.io:443"
EOF

echo "✅ Sui client configuration created"

# Set active environment
sui client switch --env testnet

echo "🔧 Creating new address for deployment..."
# Create new address (this will prompt for input, so we'll handle it manually)
echo "Please run: sui client new-address ed25519"
echo "Then run: sui client switch --address <your-new-address>"
echo "Then run: sui client faucet"
echo "Finally run: sui client publish --gas-budget 100000000"

echo "📋 Deployment steps:"
echo "1. Create new address: sui client new-address ed25519"
echo "2. Switch to new address: sui client switch --address <address>"
echo "3. Get testnet coins: sui client faucet"
echo "4. Deploy: sui client publish --gas-budget 100000000"
echo "5. Update deployments.json with the new address"

echo "🎯 Ready for deployment!" 