#!/bin/bash

echo "🔧 Creating proper Sui client configuration..."

# Create the config directory
mkdir -p ~/.sui/sui_config

# Create a minimal client.yaml that will work
cat > ~/.sui/sui_config/client.yaml << 'EOF'
---
accounts: []
active_address: null
active_env: testnet
envs:
  - alias: testnet
    rpc: "https://fullnode.testnet.sui.io:443"
    ws: "wss://fullnode.testnet.sui.io:443"
keystore:
  File: ~/.sui/sui_config/sui.keystore
EOF

echo "✅ Sui client configuration created successfully!"

# Now try to create a new address
echo "🔑 Creating new address..."
echo "0" | sui client new-address ed25519

echo "🎯 Sui client is now ready for deployment!" 