#!/bin/bash

# Sui Fusion Plus Deployment Script
# This script helps deploy the contracts to Sui testnet

set -e

echo "🚀 Starting Sui Fusion Plus Deployment to Testnet"
echo "=================================================="

# Check if we're in the right directory
if [ ! -f "Move.toml" ]; then
    echo "❌ Error: Move.toml not found. Please run this script from the sui-fusion-plus directory."
    exit 1
fi

# Step 1: Build the package
echo "📦 Building the package..."
sui move build

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
else
    echo "❌ Build failed!"
    exit 1
fi

# Step 2: Check if Sui client is configured
echo "🔧 Checking Sui client configuration..."
if ! sui client active-address &> /dev/null; then
    echo "⚠️  Sui client not configured. Please run:"
    echo "   sui client init"
    echo "   sui client new-env --alias testnet --rpc https://fullnode.testnet.sui.io:443"
    echo "   sui client switch --env testnet"
    echo "   sui client new-address ed25519"
    echo ""
    echo "Then get some testnet SUI from the faucet and run this script again."
    exit 1
fi

# Step 3: Check balance
echo "💰 Checking balance..."
BALANCE=$(sui client balance | grep "Total Balance" | awk '{print $3}' | sed 's/SUI//')
echo "Current balance: $BALANCE SUI"

# Check if balance is sufficient (at least 0.1 SUI)
if (( $(echo "$BALANCE < 0.1" | bc -l) )); then
    echo "❌ Insufficient balance. Please get testnet SUI from the faucet."
    echo "Visit: https://discord.gg/sui"
    exit 1
fi

# Step 4: Deploy to testnet
echo "🚀 Deploying to testnet..."
echo "This may take a few minutes..."

DEPLOY_RESULT=$(sui client publish --gas-budget 100000000)

if [ $? -eq 0 ]; then
    echo "✅ Deployment successful!"
    
    # Extract package ID from the result
    PACKAGE_ID=$(echo "$DEPLOY_RESULT" | grep "Created Objects:" -A 10 | grep "Immutable" | head -1 | awk '{print $2}')
    
    if [ ! -z "$PACKAGE_ID" ]; then
        echo "📦 Package ID: $PACKAGE_ID"
        
        # Save package ID to file
        echo "$PACKAGE_ID" > package_id.txt
        echo "Package ID saved to package_id.txt"
        
        # Extract other important object IDs
        echo "🔍 Extracting object IDs..."
        echo "$DEPLOY_RESULT" | grep "Created Objects:" -A 20 > deployment_details.txt
        echo "Deployment details saved to deployment_details.txt"
        
        echo ""
        echo "🎉 Deployment completed successfully!"
        echo "======================================"
        echo "📦 Package ID: $PACKAGE_ID"
        echo "📄 Check deployment_details.txt for all object IDs"
        echo ""
        echo "Next steps:"
        echo "1. Test the deployed contracts"
        echo "2. Register a resolver"
        echo "3. Create test fusion orders"
        echo "4. Monitor for any issues"
        
    else
        echo "⚠️  Could not extract package ID from deployment result"
        echo "Check the deployment output above for the package ID"
    fi
    
else
    echo "❌ Deployment failed!"
    echo "Check the error message above and try again."
    exit 1
fi

echo ""
echo "📚 For more information, see DEPLOYMENT_GUIDE.md" 