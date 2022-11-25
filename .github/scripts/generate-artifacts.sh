#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

repo_root_dir='.'
deployment_output_folder="$repo_root_dir/broadcast/Deploy.sol"

echo "Creating build artifacts..."
forge build -o artifacts

echo "Creating networks.json..."
for deployment in "$deployment_output_folder/"*; do
  # The subfolder name is the chain id
  chain_id=${deployment##*/}
  # First, every single deployment is formatted as if it had its own networks.json
  jq --arg chainId "$chain_id" '
    .transactions[]
    | select(.transactionType == "CREATE" )
    | {(.contractName): {($chainId): {address: .contractAddress, transactionHash: .hash }}}
  '  <"$deployment/deployment.json"
done \
  | # Then, all these single-contract single-chain-id networks.jsons are merged. Note: in case the same contract is
    # deployed twice in the same script run, the last deployed contract takes priority.  
    jq -n 'reduce inputs as $item ({}; . *= $item)' \
  > "$repo_root_dir/networks.json"

echo "Creating hardhat build artifacts..."
# Eventually we want to stop generating Hardhat artifacts, in the meantime we pin here a specific version
yarn add --dev "hardhat@2.12.2"
npx hardhat --config "$repo_root_dir/.github/scripts/hardhat.config.js" compile
