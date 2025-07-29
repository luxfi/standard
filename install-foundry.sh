#!/bin/bash

# Install Foundry if not installed
if ! command -v forge &> /dev/null; then
    echo "Installing Foundry..."
    curl -L https://foundry.paradigm.xyz | bash
    foundryup
fi

# Install forge-std
echo "Installing forge-std..."
forge install foundry-rs/forge-std --no-commit

# Install OpenZeppelin contracts v5
echo "Installing OpenZeppelin contracts..."
forge install OpenZeppelin/openzeppelin-contracts@v5.0.1 --no-commit

# Create lib directory if it doesn't exist
mkdir -p lib

echo "Foundry dependencies installed successfully!"