#!/bin/bash

# Function to calculate the SHA-256 hash of a file
calculate_sha256() {
    sha256sum "$1" | awk '{ print $1 }'
}

# Function to verify signatures using GPG with the imported public keys
verify_signatures() {
    local signatures_file="$1"
    gpg --verify "$signatures_file" &>/dev/null
    if [ $? -eq 0 ]; then
        echo "Binary signature verification successful."
    else
        echo "Signature verification failed for $signatures_file. The binary may have been tampered with."
        exit 1
    fi
}

# Function to verify the SHA-256 checksum of the downloaded binary
verify_checksum() {
    local provided_checksum="33930d432593e49d58a9bff4c30078823e9af5d98594d2935862788ce8a20aec"
    local downloaded_binary="$1"

    # Verify the downloaded binary's SHA-256 hash
    local calculated_checksum=$(calculate_sha256 "$downloaded_binary")

    if [ "$calculated_checksum" = "$provided_checksum" ]; then
        echo "Binary SHA-256 hash verification successful."
        # verify_signatures "SHA256SUMS.asc"
        verify_signatures "/home/shreyan/Downloads/SHA256SUMS.asc"

        # gpg --verify /home/shreyan/Downloads/SHA256SUMS.asc
        echo "Copying the extracted binaries to /usr/local/bin/..."
        tar -xzvf "$downloaded_binary" bitcoin-25.0/bin/
        sudo cp bitcoin-25.0/bin/* /usr/local/bin/ || exit 1
        echo "Bitcoin Core binaries copied to /usr/local/bin/"
    else
        echo "Binary SHA-256 hash verification failed. The binary may have been tampered with."
        exit 1
    fi
}

# Main script
 
# Download Bitcoin Core binary for Linux x86-64
download_url="https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-x86_64-linux-gnu.tar.gz"
downloaded_binary="bitcoin-25.0-x86_64-linux-gnu.tar.gz"
 
echo "Downloading Bitcoin Core binary for x86-64-linux-gnu..."
if wget "$download_url"; then
   echo "Download complete."
   verify_checksum "$downloaded_binary"
else
   echo "Failed to download Bitcoin Core binary."
   exit 1
fi




# Set the data directory for the Bitcoin Core
bitcoin_data_dir="/home/shreyan/.bitcoin/"

# Create the data directory if it doesn't exist
mkdir -p "$bitcoin_data_dir"

# Create and populate the bitcoin.conf file
echo "regtest=1" > "$bitcoin_data_dir/bitcoin.conf"
echo "fallbackfee=0.0001" >> "$bitcoin_data_dir/bitcoin.conf"
echo "server=1" >> "$bitcoin_data_dir/bitcoin.conf"
echo "txindex=1" >> "$bitcoin_data_dir/bitcoin.conf"

# Start bitcoind
bitcoind -regtest -daemon

# Wait for bitcoind to start
sleep 2

# Create the Miner Wallet
bitcoin-cli -rpcwallet= createwallet Miner

# Create the Trader Wallet
bitcoin-cli -rpcwallet= createwallet Trader

# Generate an address for Miner wallet with the label “Mining Reward”
mining_reward_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Mining Reward")
echo "Mining Reward Address: $mining_reward_address"

# Mine Blocks
blocks_to_mine=100
bitcoin-cli -rpcwallet=Miner generatetoaddress "$blocks_to_mine" "$mining_reward_address"

# Note on why wallet balance for block rewards behaves this way
: '
In regtest mode, the mining rewards are subject to a maturity period
and require additional block confirmations, even though mining itself
is much faster and easier than in the mainnet or testnet. This is to
ensure a more realistic testing environment for developers while
allowing for rapid testing and experimentation.
'

# Check the balance to verify it is in the immature state
bitcoin-cli -rpcwallet=Miner getwalletinfo

# Print the Miner Wallet Balance
miner_balance=$(bitcoin-cli -rpcwallet=Miner getbalance)
echo "Miner Wallet Balance: $miner_balance BTC"

# Step 1: Create a receiving address labeled "Received" from Trader wallet.
echo "Creating a receiving address for Trader.."
trader_address=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Received")
echo "Transaction address: $trader_address"

# Step 2: Send a transaction paying 20 BTC from Miner wallet to Trader's wallet.
echo "Sending 20BTC from the Miner to the Trader.."
transaction_id=$(bitcoin-cli -rpcwallet=Miner sendtoaddress "$trader_address" 20)
echo "Transaction ID: $transaction_id"

# Step 3: Fetch the unconfirmed transaction from the node's mempool and print the result.
unconfirmed_transaction=$(bitcoin-cli -rpcwallet=Miner getmempoolentry "$transaction_id")
echo "Fetching the unconfirmed transaction from the mempool.."
echo "Unconfirmed transaction: $unconfirmed_transaction"

# Step 4: Confirm the transaction by creating 1 more block.
echo "Transaction confirmed in block:"
bitcoin-cli -rpcwallet=Miner -generate 1

# Step 5: Fetch the details of the transaction and print them into the terminal.
transaction_details=$(bitcoin-cli -rpcwallet=Miner gettransaction $transaction_id)

# Extracting required information from the transaction details.
from_address=$(echo "$transaction_details" | jq '.details[0].address')
input_amount=$(echo "$transaction_details" | jq '.details[0].amount')
send_amount=$(echo "$transaction_details" | jq '.details[1].amount')
change_amount=$(echo "$transaction_details" | jq '.details[2].amount')
fees_amount=$(echo "$transaction_details" | jq '.fee')
block_height=$(bitcoin-cli getblockcount)

# Step 6: Fetch the balances of the Miner and Trader wallets after the transaction.
miner_balance=$(bitcoin-cli -rpcwallet=Miner getbalance)
trader_balance=$(bitcoin-cli -rpcwallet=Trader getbalance)

# Printing the required information.
echo "Transaction Details:"
echo "txid: $transaction_id"
echo "<From, Amount>: $from_address, $input_amount"
echo "<Send, Amount>: $trader_address, $send_amount"
echo "<Change, Amount>: $from_address, $change_amount"
echo "Fees: $fees_amount"
echo "Block: $block_height"
echo "Miner Balance: $miner_balance"
echo "Trader Balance: $trader_balance"

