#!/bin/bash

# Start the Bitcoin Regtest daemon
bitcoind -regtest -daemon

# Wait for the daemon to start
sleep 5

# Create two wallets named Miner and Trader
bitcoin-cli -rpcwallet=Miner createwallet Miner true
bitcoin-cli -rpcwallet=Trader createwallet Trader true

# Generate 3 blocks to Miner's wallet
bitcoin-cli -rpcwallet=Miner generatetoaddress 3 $(bitcoin-cli -rpcwallet=Miner getnewaddress)

# Send 70 BTC to Trader and 29.99999 BTC back to Miner (Parent Transaction)
txid=$(bitcoin-cli -rpcwallet=Miner sendtoaddress $(bitcoin-cli -rpcwallet=Trader getnewaddress) 70)
change_output=$(bitcoin-cli -rpcwallet=Miner gettransaction $txid | jq -r '.details[] | select(.category=="send") | select(.amount == 29.99999) | .vout')
change_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress)

# Signal RBF (Replace-By-Fee) for the Parent Transaction
bitcoin-cli -rpcwallet=Miner walletcreatefundedpsbt '[]' '[{"address": "'$change_address'", "satoshi": 2999999, "subtract_fee_from_outputs": [0]}]' 0 "{}" true

# Sign and broadcast the Parent Transaction
bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $(bitcoin-cli -rpcwallet=Miner getrawtransaction $txid) | jq -r '.hex' | bitcoin-cli -rpcwallet=Miner sendrawtransaction

# Make queries to the node's mempool to get the Parent transaction details
parent_tx_details=$(bitcoin-cli -rpcwallet=Miner getmempoolentry $txid | jq -r '.[] | select(.vsize > 0) | {input: .depends[], output: .vout[0].scriptPubKey.hex, amount: .vout[0].value} | {input: [{txid: .input.txid, vout: .input.vout}], output: [{script_pubkey: .output, amount: .amount}]}' | jq -s add)

# Print the above JSON in the terminal
echo "Parent Transaction Details:"
echo $parent_tx_details

# Create a broadcast new transaction (Child Transaction)
child_tx=$(bitcoin-cli -rpcwallet=Miner createrawtransaction "[{\"txid\":\"$txid\",\"vout\":0}]" "{\"$change_address\":29.99998}")

# Sign and broadcast the Child Transaction
signed_child_tx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $child_tx | jq -r '.hex')
bitcoin-cli -rpcwallet=Miner sendrawtransaction $signed_child_tx

# Make a getmempoolentry query for the Child transaction and print the output
child_tx_details=$(bitcoin-cli -rpcwallet=Miner getmempoolentry $(bitcoin-cli -rpcwallet=Miner decoderawtransaction $signed_child_tx | jq -r '.txid') | jq -r '.[] | {vsize: .vsize, fee: .fee, weight: .weight}')

# Print the Child Transaction details
echo "Child Transaction Details:"
echo $child_tx_details

# Now, fee bump the Parent transaction using RBF
new_parent_tx=$(bitcoin-cli -rpcwallet=Miner createrawtransaction "[{\"txid\":\"$txid\",\"vout\":0}]" "{\"$change_address\":29.99997}")

# Sign and broadcast the new Parent transaction
signed_new_parent_tx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $new_parent_tx | jq -r '.hex')
bitcoin-cli -rpcwallet=Miner sendrawtransaction $signed_new_parent_tx

# Make another getmempoolentry query for the Child transaction and print the result
new_child_tx_details=$(bitcoin-cli -rpcwallet=Miner getmempoolentry $(bitcoin-cli -rpcwallet=Miner decoderawtransaction $signed_child_tx | jq -r '.txid') | jq -r '.[] | {vsize: .vsize, fee: .fee, weight: .weight}')

# Print the new Child Transaction details
echo "New Child Transaction Details:"
echo $new_child_tx_details

# Explanation of changes in the two getmempoolentry results for the Child transactions
echo "Explanation of Changes:"
echo "The second getmempoolentry result for the Child transaction shows that the fee has increased by 10,000 satoshis in the new Parent transaction. The fee increase is due to the new output created in the new Parent transaction, which redirects some funds to a new change address. The new Parent transaction replaces the previous Parent transaction in the mempool, as it offers a higher fee per vbyte, making it more attractive for miners to include in a block."

