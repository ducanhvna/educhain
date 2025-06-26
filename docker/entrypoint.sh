#!/bin/sh
set -e

# For debugging
set -x

# Place all helper functions here so they are available before any logic uses them

# Hàm để kiểm tra và kill các process sử dụng một thư mục
safe_kill_processes() {
  dir="$1"
  echo "🔍 Kiểm tra các process đang sử dụng thư mục $dir..."

  # Cố gắng lấy danh sách pid
  pids=$(lsof -t "$dir" 2>/dev/null || true)

  if [ -n "$pids" ]; then
    for pid in $pids; do
      echo "🛑 Tìm thấy process $pid đang sử dụng $dir, đang dừng..."
      kill -9 $pid 2>/dev/null || true
    done
    # Đợi một chút để các process có thời gian dừng
    sleep 3
  else
    echo "✅ Không có process nào đang sử dụng $dir"
  fi
}

# Hàm để xóa thư mục an toàn
safe_remove_dir() {
  dir="$1"
  if [ -d "$dir" ]; then
    safe_kill_processes "$dir"
    echo "🗑️ Đang xóa thư mục $dir..."
    rm -rf "$dir" 2>/dev/null || {
      echo "⚠️ Không thể xóa thư mục $dir, thử phương pháp khác..."
      find "$dir" -type f -delete 2>/dev/null || true
      find "$dir" -type d -delete 2>/dev/null || true
    }
  fi
}

# Function to validate a genesis file more thoroughly
validate_genesis() {
  genesis_file="$1"
  echo "🔍 Validating genesis file: $genesis_file"
  # Check if the file exists
  if [ ! -f "$genesis_file" ]; then
    echo "❌ Genesis file does not exist!"
    return 1
  fi
  # Check if it's valid JSON
  if ! jq . "$genesis_file" > /dev/null 2>&1; then
    echo "❌ Genesis file is not valid JSON!"
    return 1
  fi
  # Check if there's at least one validator with sufficient power
  validator_count=$(jq '.app_state.staking.validators | length' "$genesis_file")
  if [ "$validator_count" -eq 0 ]; then
    echo "❌ No validators found in genesis file!"
    return 1
  fi
  # Check if the validator has sufficient tokens (should be above 1_000_000_000_000_000)
  validator_tokens=$(jq -r '.app_state.staking.validators[0].tokens' "$genesis_file")
  if [ -z "$validator_tokens" ] || [ "$validator_tokens" -lt 1000000000000000 ]; then
    echo "❌ Validator tokens are insufficient: $validator_tokens"
    echo "   Must be at least 1_000_000_000_000_000"
    return 1
  fi
  # Check if there's at least one delegation
  delegation_count=$(jq '.app_state.staking.delegations | length' "$genesis_file")
  if [ "$delegation_count" -eq 0 ]; then
    echo "❌ No delegations found in genesis file!"
    return 1
  fi
  # All checks passed
  echo "✅ Genesis file validation passed!"
  return 0
}

# Function to fix the validator's power if it's too low
fix_validator_power() {
  genesis_file="$1"
  min_power="1000000000000000" # 10^15
  echo "🔍 Checking validator power in genesis file: $genesis_file"
  # First check if the file exists and is valid JSON
  if [ ! -f "$genesis_file" ] || ! jq . "$genesis_file" > /dev/null 2>&1; then
    echo "❌ Invalid or non-existent genesis file!"
    return 1
  fi
  # Make a backup of the genesis file
  backup_file="${genesis_file}.backup.$(date +%s)"
  cp "$genesis_file" "$backup_file"
  echo "📤 Backup created: $backup_file"
  # Check if there are validators
  validator_count=$(jq '.app_state.staking.validators | length' "$genesis_file")
  echo "📊 Current validator count: $validator_count"
  if [ "$validator_count" -eq 0 ]; then
    echo "❌ No validators found in app_state.staking.validators!"
    echo "🔧 Cannot fix validator power - no validators to update."
    return 1
  fi
  # Check if there are validators in the top-level validators array
  top_validators=$(jq '.validators | length' "$genesis_file")
  echo "📊 Current top-level validators count: $top_validators"
  # Check the validator's tokens
  token_value=$(jq -r '.app_state.staking.validators[0].tokens' "$genesis_file")
  echo "📊 Current validator tokens: $token_value"
  # Update the power values using a very large number to ensure it's above DefaultPowerReduction
  new_token_value="10000000000000000000000" # 10^22
  new_power_value="10000000" # 10^7
  echo "🔧 Updating validator tokens to $new_token_value..."
  echo "🔧 Updating validator power to $new_power_value..."
  # Create temporary file
  temp_file="${genesis_file}.tmp"
  # Update the validator's tokens and delegator_shares
  shares_value="${new_token_value}.000000000000000000"
  jq --arg tokens "$new_token_value" --arg shares "$shares_value" '.app_state.staking.validators[0].tokens = $tokens | .app_state.staking.validators[0].delegator_shares = $shares' "$genesis_file" > "$temp_file"
  # Update delegations
  jq --arg shares "$shares_value" \
    'if .app_state.staking.delegations | length > 0 then
      .app_state.staking.delegations[0].shares = $shares
    else
      .
    end' "$temp_file" > "${temp_file}2"
  # Update the last_total_power and validator power
  jq --arg power "$new_power_value" \
    '.app_state.staking.last_total_power = $power |
    if .app_state.staking.last_validator_powers | length > 0 then
      .app_state.staking.last_validator_powers[0].power = $power
    else
      .
    end' "${temp_file}2" > "${temp_file}3"
  # Update validators array if it exists
  jq --arg power "$new_power_value" \
    'if has("validators") and (.validators | length > 0) then
      .validators[0].power = $power
    else
      .
    end' "${temp_file}3" > "${temp_file}4"
  # Move the final result back to the original file
  mv "${temp_file}4" "$genesis_file"
  # Cleanup temporary files
  rm -f "$temp_file" "${temp_file}2" "${temp_file}3"
  echo "✅ Validator power and tokens updated in genesis file!"
  # Verify the changes
  echo "📊 Verification after update:"
  echo "Validator tokens: $(jq -r '.app_state.staking.validators[0].tokens' "$genesis_file")"
  echo "Delegator shares: $(jq -r '.app_state.staking.validators[0].delegator_shares' "$genesis_file")"
  echo "Last total power: $(jq -r '.app_state.staking.last_total_power' "$genesis_file")"
  if jq -e '.app_state.staking.last_validator_powers | length > 0' "$genesis_file" > /dev/null; then
    echo "Last validator power: $(jq -r '.app_state.staking.last_validator_powers[0].power' "$genesis_file")"
  fi
  if jq -e '.validators | length > 0' "$genesis_file" > /dev/null; then
    echo "Top-level validator power: $(jq -r '.validators[0].power' "$genesis_file")"
  fi
  return 0
}

# Function to ensure the genesis file has a validator with sufficient power
ensure_validator_exists() {
  genesis_file="$1"
  val_address="$2"
  pubkey_type="$3"
  pubkey_key="$4"
  moniker="$5"
  echo "🔍 Ensuring validator exists in genesis file: $genesis_file"
  # First check if the file exists and is valid JSON
  if [ ! -f "$genesis_file" ] || ! jq . "$genesis_file" > /dev/null 2>&1; then
    echo "❌ Invalid or non-existent genesis file!"
    return 1
  fi
  # Check if there are validators
  validator_count=$(jq '.app_state.staking.validators | length' "$genesis_file")
  echo "📊 Current validator count: $validator_count"
  if [ "$validator_count" -eq 0 ]; then
    echo "⚠️ No validators found in app_state.staking.validators, adding one..."
    # Create a backup of the genesis file
    backup_file="${genesis_file}.backup.$(date +%s)"
    cp "$genesis_file" "$backup_file"
    echo "📤 Backup created: $backup_file"
    # Define token and power values
    token_value="10000000000000000000000" # 10^22
    power_value="10000000" # 10^7
    # Add validator to staking.validators
    jq --arg addr "$val_address" \
       --arg pubkey_type "$pubkey_type" \
       --arg pubkey_key "$pubkey_key" \
       --arg moniker "$moniker" \
       --arg tokens "$token_value" \
       --arg shares "$token_value.000000000000000000" \
    '.app_state.staking.validators += [{
      "operator_address": $addr,
      "consensus_pubkey": {
        "@type": $pubkey_type,
        "key": $pubkey_key
      },
      "jailed": false,
      "status": "BOND_STATUS_BONDED",
      "tokens": $tokens,
      "delegator_shares": $shares,
      "description": {
        "moniker": $moniker,
        "identity": "",
        "website": "",
        "security_contact": "",
        "details": ""
      },
      "unbonding_height": "0",
      "unbonding_time": "1970-01-01T00:00:00Z",
      "commission": {
        "commission_rates": {
          "rate": "0.100000000000000000",
          "max_rate": "0.200000000000000000",
          "max_change_rate": "0.010000000000000000"
        },
        "update_time": "2023-01-01T00:00:00Z"
      },
      "min_self_delegation": "1"
    }]' "$genesis_file" > "${genesis_file}.tmp"
    # Add delegation
    jq --arg del_addr "$val_address" \
       --arg val_addr "$val_address" \
       --arg shares "$token_value.000000000000000000" \
    '.app_state.staking.delegations += [{
      "delegator_address": $del_addr,
      "validator_address": $val_addr,
      "shares": $shares
    }]' "${genesis_file}.tmp" > "${genesis_file}.tmp2"
    # Update last_total_power
    jq --arg power "$power_value" \
    '.app_state.staking.last_total_power = $power' "${genesis_file}.tmp2" > "${genesis_file}.tmp3"
    # Add to last_validator_powers
    jq --arg val_addr "$val_address" \
       --arg power "$power_value" \
    '.app_state.staking.last_validator_powers += [{
      "address": $val_addr,
      "power": $power
    }]' "${genesis_file}.tmp3" > "${genesis_file}.tmp4"
    # Add to top-level validators array
    jq --arg pubkey_type "$pubkey_type" \
       --arg pubkey_key "$pubkey_key" \
       --arg power "$power_value" \
    'if has("validators") then
      .validators += [{
        "address": "",
        "pub_key": {
          "@type": $pubkey_type,
          "key": $pubkey_key
        },
        "power": $power,
        "name": ""
      }]
    else
      . + {
        "validators": [{
          "address": "",
          "pub_key": {
            "@type": $pubkey_type,
            "key": $pubkey_key
          },
          "power": $power,
          "name": ""
        }]
      }
    end' "${genesis_file}.tmp4" > "${genesis_file}.tmp5"
    # Move the final result back to the original file
    mv "${genesis_file}.tmp5" "$genesis_file"
    # Cleanup temporary files
    rm -f "${genesis_file}.tmp" "${genesis_file}.tmp2" "${genesis_file}.tmp3" "${genesis_file}.tmp4"
    echo "✅ Validator added to genesis file!"
    # Verify the changes
    validator_count=$(jq '.app_state.staking.validators | length' "$genesis_file")
    echo "📊 New validator count: $validator_count"
    return 0
  else
    echo "✅ Validators already exist in genesis file."
    return 0
  fi
}

# Helper: Convert wasm address to wasmvaloper address
bech32_to_valoper() {
  wasm_addr="$1"
  # Use the bech32 utility if available, else fail with error
  if command -v bech32 >/dev/null 2>&1; then
    echo "$wasm_addr" | bech32 wasmvaloper | tail -n1
  else
    echo "❌ Lỗi: Không tìm thấy lệnh 'bech32'. Vui lòng cài đặt gói bech32 trong Dockerfile (apk add bech32 hoặc bech32-utils)." >&2
    exit 1
  fi
}

# Fix operator_address in staking.validators if needed
fix_validator_operator_address() {
  genesis_file="$1"
  echo "🔍 Kiểm tra operator_address trong staking.validators..."
  addr=$(jq -r '.app_state.staking.validators[0].operator_address' "$genesis_file")
  case "$addr" in
    wasm1*)
      case "$addr" in
        wasmvaloper1*)
          echo "✅ operator_address đã đúng prefix."
          ;;
        *)
          echo "⚠️ Địa chỉ operator_address sai prefix: $addr"
          valoper_addr=$(bech32_to_valoper "$addr")
          if [ -z "$valoper_addr" ]; then
            echo "❌ Không thể chuyển đổi sang wasmvaloper. Dừng lại."
            exit 1
          fi
          echo "🔧 Đổi operator_address thành $valoper_addr"
          jq --arg new_addr "$valoper_addr" '.app_state.staking.validators[0].operator_address = $new_addr' "$genesis_file" > "${genesis_file}.tmp" && mv "${genesis_file}.tmp" "$genesis_file"
          # Sửa validator_address trong delegations nếu có
          delegations_count=$(jq '.app_state.staking.delegations | length' "$genesis_file")
          if [ "$delegations_count" -gt 0 ]; then
            jq --arg new_addr "$valoper_addr" '.app_state.staking.delegations[0].validator_address = $new_addr' "$genesis_file" > "${genesis_file}.tmp" && mv "${genesis_file}.tmp" "$genesis_file"
          fi
          # Sửa address trong last_validator_powers nếu có
          powers_count=$(jq '.app_state.staking.last_validator_powers | length' "$genesis_file")
          if [ "$powers_count" -gt 0 ]; then
            jq --arg new_addr "$valoper_addr" '.app_state.staking.last_validator_powers[0].address = $new_addr' "$genesis_file" > "${genesis_file}.tmp" && mv "${genesis_file}.tmp" "$genesis_file"
          fi
          echo "✅ Đã sửa operator_address sang wasmvaloper."
          ;;
      esac
      ;;
    *)
      echo "✅ Không có validator hoặc operator_address không phải wasm1..."
      ;;
  esac
}

MONIKER=${MONIKER:-"node1"}
CHAIN_ID="educhain-1"
HOME_DIR="/root/.wasmd"
CONFIG="$HOME_DIR/config/config.toml"
APP="$HOME_DIR/config/app.toml"
GENESIS_SHARED="/shared/genesis.json"
GENESIS_FILE="$HOME_DIR/config/genesis.json"

echo "🚀 Khởi động entrypoint cho $MONIKER"

# Khởi tạo node nếu chưa hoặc genesis.json rỗng
if [ ! -s "$GENESIS_FILE" ] || [ ! -f "$HOME_DIR/config/priv_validator_key.json" ] || [ "$RESET_NODE" = "true" ]; then
  # Nếu đã tồn tại, sao lưu trước khi xoá
  if [ -d "$HOME_DIR" ]; then
    echo "⚠️ Sao lưu dữ liệu node trước khi khởi tạo lại..."
    # Sao lưu các file quan trọng
    if [ -f "$HOME_DIR/config/priv_validator_key.json" ]; then
      cp "$HOME_DIR/config/priv_validator_key.json" "/tmp/priv_validator_key.json.backup"
    fi
    
    # Xóa an toàn thư mục cấu hình và data
    echo "🗑️ Xóa thư mục cấu hình cũ để khởi tạo mới hoàn toàn..."
    safe_remove_dir "$HOME_DIR/config"
    safe_remove_dir "$HOME_DIR/data"
  fi
  
  echo "⚠️ genesis.json hoặc validator key bị thiếu. Khởi tạo lại..."
  wasmd init "$MONIKER" --chain-id "$CHAIN_ID" --home "$HOME_DIR"
  
  # Thiết lập minimum-gas-prices ngay từ đầu
  echo "🔧 Thiết lập minimum-gas-prices ngay sau khi khởi tạo..."
  sed -i 's/^minimum-gas-prices *=.*/minimum-gas-prices = "0.025stake"/' "$APP"
  
  # Kiểm tra xem genesis.json đã được tạo đúng chưa
  if [ ! -s "$GENESIS_FILE" ]; then
    echo "❌ [ERROR] Không thể tạo genesis.json"
    exit 1
  fi
  
  # Kiểm tra xem validator key đã được tạo đúng chưa
  if [ ! -f "$HOME_DIR/config/priv_validator_key.json" ]; then
    echo "❌ [ERROR] Không thể tạo validator key"
    exit 1
  fi
  
  # Kiểm tra genesis.json hợp lệ không
  echo "🔍 Kiểm tra genesis.json mới tạo có hợp lệ không..."
  wasmd genesis validate-genesis --home "$HOME_DIR" || {
    echo "❌ [ERROR] Genesis mới tạo không hợp lệ!"
    exit 1
  }
fi

# Cấu hình RPC và P2P
sed -i "s/^moniker *=.*/moniker = \"$MONIKER\"/" "$CONFIG"
sed -i "s/^rpc.laddr *=.*/rpc.laddr = \"tcp:\/\/0.0.0.0:26657\"/" "$CONFIG"
sed -i "s/^laddr *=.*/laddr = \"tcp:\/\/0.0.0.0:26656\"/" "$CONFIG"

# Tắt pruning để tránh lỗi
sed -i 's/^pruning *=.*/pruning = "nothing"/' "$APP"
# Đảm bảo minimum-gas-prices được đặt đúng trong app.toml
sed -i 's/^minimum-gas-prices *=.*/minimum-gas-prices = "0.025stake"/' "$APP"
# Thêm kiểm tra và tìm để đảm bảo đã thiết lập đúng
if ! grep -q "^minimum-gas-prices" "$APP"; then
  echo "minimum-gas-prices = \"0.025stake\"" >> "$APP"
fi

# Đồng bộ genesis giữa các node
if [ "$MONIKER" = "node1" ]; then
  echo "🔐 Tạo validator đơn giản..."
  
  # 1. Xóa thư mục keyring-test nếu tồn tại
  rm -rf "$HOME_DIR/keyring-test"
  
  # 2. Tạo tài khoản wallet và validator
  echo "🔑 Tạo tài khoản..."
  wasmd keys add validator --keyring-backend test --home "$HOME_DIR"
  wasmd keys add wallet --keyring-backend test --home "$HOME_DIR"
  
  VAL_ADDRESS=$(wasmd keys show validator -a --keyring-backend test --home "$HOME_DIR")
  WALLET_ADDRESS=$(wasmd keys show wallet -a --keyring-backend test --home "$HOME_DIR")
  echo "💼 Địa chỉ validator: $VAL_ADDRESS"
  echo "💼 Địa chỉ wallet: $WALLET_ADDRESS"
  
  # Lấy thông tin validator pubkey
  VAL_PUBKEY=$(wasmd tendermint show-validator --home "$HOME_DIR")
  echo "🔑 Validator Pubkey: $VAL_PUBKEY"
  VAL_PUBKEY_TYPE=$(echo "$VAL_PUBKEY" | jq -r '."@type"')
  VAL_PUBKEY_KEY=$(echo "$VAL_PUBKEY" | jq -r '.key')
  echo "🔑 Pubkey Type: $VAL_PUBKEY_TYPE"
  echo "🔑 Pubkey Key: $VAL_PUBKEY_KEY"

  # Lấy node_id để các nodes khác có thể connect
  NODE_ID=$(wasmd tendermint show-node-id --home "$HOME_DIR")
  echo "🔑 Node ID: $NODE_ID"
  
  # Tạo genesis.json mới
  echo "📝 Cập nhật genesis.json..."
  
  # Cập nhật genesis_time
  GENESIS_TIME=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  GENESIS=$(cat "$GENESIS_FILE")
  GENESIS=$(echo "$GENESIS" | jq --arg time "$GENESIS_TIME" '.genesis_time = $time')
  
  # Cập nhật consensus_params
  GENESIS=$(echo "$GENESIS" | jq '.consensus_params.block.max_bytes = "22020096"')
  GENESIS=$(echo "$GENESIS" | jq '.consensus_params.block.max_gas = "-1"')
  GENESIS=$(echo "$GENESIS" | jq '.consensus_params.evidence.max_age_num_blocks = "100000"')
  GENESIS=$(echo "$GENESIS" | jq '.consensus_params.evidence.max_age_duration = "172800000000000"')
  
  # Xác định đúng loại pubkey
  if [[ "$VAL_PUBKEY_TYPE" == *"secp256k1"* ]]; then
    echo "🔐 Sử dụng secp256k1 pubkey type"
    GENESIS=$(echo "$GENESIS" | jq '.consensus_params.validator.pub_key_types = ["secp256k1"]')
  else
    echo "🔐 Sử dụng ed25519 pubkey type"
    GENESIS=$(echo "$GENESIS" | jq '.consensus_params.validator.pub_key_types = ["ed25519"]')
  fi
  
  # Cập nhật app_state auth
  GENESIS=$(echo "$GENESIS" | jq '.app_state.auth.params.max_memo_characters = "256"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.auth.params.tx_sig_limit = "7"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.auth.params.tx_size_cost_per_byte = "10"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.auth.params.sig_verify_cost_ed25519 = "590"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.auth.params.sig_verify_cost_secp256k1 = "1000"')
  
  # Cập nhật app_state bank
  GENESIS=$(echo "$GENESIS" | jq '.app_state.bank.params.default_send_enabled = true')
  
  # Thêm validator vào accounts
  GENESIS=$(echo "$GENESIS" | jq --arg addr "$VAL_ADDRESS" '
  .app_state.auth.accounts += [{
    "@type": "/cosmos.auth.v1beta1.BaseAccount",
    "address": $addr,
    "pub_key": null,
    "account_number": "0",
    "sequence": "0"
  }]')
  
  # Thêm wallet vào accounts
  GENESIS=$(echo "$GENESIS" | jq --arg addr "$WALLET_ADDRESS" '
  .app_state.auth.accounts += [{
    "@type": "/cosmos.auth.v1beta1.BaseAccount",
    "address": $addr,
    "pub_key": null,
    "account_number": "1",
    "sequence": "0"
  }]')
  
  # Thêm balances
  GENESIS=$(echo "$GENESIS" | jq --arg addr "$VAL_ADDRESS" '
  .app_state.bank.balances += [{
    "address": $addr,
    "coins": [
      {
        "denom": "stake",
        "amount": "1000000000"
      }
    ]
  }]')
  
  GENESIS=$(echo "$GENESIS" | jq --arg addr "$WALLET_ADDRESS" '
  .app_state.bank.balances += [{
    "address": $addr,
    "coins": [
      {
        "denom": "stake",
        "amount": "1000000000"
      }
    ]
  }]')
  
  # Cập nhật denom_metadata
  GENESIS=$(echo "$GENESIS" | jq '.app_state.bank.denom_metadata += [
    {
      "description": "The native staking token of EduChain",
      "denom_units": [
        {
          "denom": "stake",
          "exponent": 0
        }
      ],
      "base": "stake",
      "display": "stake",
      "name": "STAKE",
      "symbol": "STAKE"
    }
  ]')
  
  # Cập nhật supply
  GENESIS=$(echo "$GENESIS" | jq '.app_state.bank.supply += [
    {
      "denom": "stake",
      "amount": "2000000000"
    }
  ]')
  
  # Cập nhật staking params
  GENESIS=$(echo "$GENESIS" | jq '.app_state.staking.params.unbonding_time = "1814400s"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.staking.params.max_validators = 100')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.staking.params.max_entries = 7')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.staking.params.historical_entries = 10000')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.staking.params.bond_denom = "stake"')
  
  # Thêm validator vào validator list
  GENESIS=$(echo "$GENESIS" | jq --arg addr "$VAL_ADDRESS" --arg pubkey_type "$VAL_PUBKEY_TYPE" --arg pubkey_key "$VAL_PUBKEY_KEY" --arg moniker "$MONIKER" '
  .app_state.staking.validators += [{
    "operator_address": $addr,
    "consensus_pubkey": {
      "@type": $pubkey_type,
      "key": $pubkey_key
    },
    "jailed": false,
    "status": "BOND_STATUS_BONDED",
    "tokens": "10000000000000000000000",
    "delegator_shares": "10000000000000000000000.000000000000000000",
    "description": {
      "moniker": $moniker,
      "identity": "",
      "website": "",
      "security_contact": "",
      "details": ""
    },
    "unbonding_height": "0",
    "unbonding_time": "1970-01-01T00:00:00Z",
    "commission": {
      "commission_rates": {
        "rate": "0.100000000000000000",
        "max_rate": "0.200000000000000000",
        "max_change_rate": "0.010000000000000000"
      },
      "update_time": "2023-01-01T00:00:00Z"
    },
    "min_self_delegation": "1"
  }]')
  
  # Thêm delegation
  GENESIS=$(echo "$GENESIS" | jq --arg del_addr "$VAL_ADDRESS" --arg val_addr "$VAL_ADDRESS" '
  .app_state.staking.delegations += [{
    "delegator_address": $del_addr,
    "validator_address": $val_addr,
    "shares": "10000000000000000000000.000000000000000000"
  }]')
  
  # Cập nhật last_total_power
  GENESIS=$(echo "$GENESIS" | jq '.app_state.staking.last_total_power = "10000000"')
  
  # Cập nhật last_validator_powers
  GENESIS=$(echo "$GENESIS" | jq --arg val_addr "$VAL_ADDRESS" '
  .app_state.staking.last_validator_powers += [{
    "address": $val_addr,
    "power": "10000000"
  }]')
  
  # Cập nhật distribution params
  GENESIS=$(echo "$GENESIS" | jq '.app_state.distribution.params.community_tax = "0.020000000000000000"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.distribution.params.base_proposer_reward = "0.010000000000000000"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.distribution.params.bonus_proposer_reward = "0.040000000000000000"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.distribution.params.withdraw_addr_enabled = true')
  
  # Cập nhật gov params
  GENESIS=$(echo "$GENESIS" | jq '.app_state.gov.params.voting_period = "172800s"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.gov.params.max_deposit_period = "172800s"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.gov.params.quorum = "0.334000000000000000"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.gov.params.threshold = "0.500000000000000000"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.gov.params.veto_threshold = "0.334000000000000000"')
  
  # Cập nhật wasm params
  GENESIS=$(echo "$GENESIS" | jq '.app_state.wasm.params.code_upload_access.permission = "Everybody"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.wasm.params.instantiate_default_permission = "Everybody"')
  
  # Cập nhật slashing params
  GENESIS=$(echo "$GENESIS" | jq '.app_state.slashing.params.signed_blocks_window = "100"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.slashing.params.min_signed_per_window = "0.500000000000000000"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.slashing.params.downtime_jail_duration = "600s"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.slashing.params.slash_fraction_double_sign = "0.050000000000000000"')
  GENESIS=$(echo "$GENESIS" | jq '.app_state.slashing.params.slash_fraction_downtime = "0.010000000000000000"')
  
  # Thêm validator vào bộ validators
  if echo "$GENESIS" | jq -e '.validators' > /dev/null 2>&1; then
    echo "📝 Thêm validator vào .validators (cách 1)..."
    GENESIS=$(echo "$GENESIS" | jq --arg pubkey_key "$VAL_PUBKEY_KEY" --arg pubkey_type "$VAL_PUBKEY_TYPE" '
    .validators += [{
      "address": "",
      "pub_key": {
        "@type": $pubkey_type,
        "key": $pubkey_key
      },
      "power": "10000000",
      "name": ""
    }]')
  else
    echo "📝 Thêm validator vào .validators (cách 2)..."
    GENESIS=$(echo "$GENESIS" | jq --arg pubkey_key "$VAL_PUBKEY_KEY" --arg pubkey_type "$VAL_PUBKEY_TYPE" '. + {
      "validators": [{
        "address": "",
        "pub_key": {
          "@type": $pubkey_type,
          "key": $pubkey_key
        },
        "power": "1000000000",
        "name": ""
      }]
    }')
  fi
  
  # Tạo bản sao lưu của genesis.json gốc
  echo "📤 Tạo bản sao lưu của genesis.json gốc..."
  cp "$GENESIS_FILE" "${GENESIS_FILE}.backup.$(date +%s)"
  
  # Ghi lại genesis.json
  echo "$GENESIS" > "$GENESIS_FILE"

  # Sửa operator_address nếu bị sai prefix
  fix_validator_operator_address "$GENESIS_FILE"

  # Kiểm tra genesis.json hợp lệ không
  echo "🔍 Kiểm tra genesis.json hợp lệ..."
  jq . "$GENESIS_FILE" > /dev/null 2>&1 || {
    echo "❌ [ERROR] Genesis không phải là JSON hợp lệ, khôi phục từ bản sao lưu..."
    cp "${GENESIS_FILE}.backup.$(date +%s)" "$GENESIS_FILE"
    exit 1
  }
  
  # DEBUG: Print important parts of genesis.json to verify validator setup
  echo "🔍 DEBUG: Checking genesis.json content before startup..."
  echo "Validator count: $(jq '.app_state.staking.validators | length' "$GENESIS_FILE")"
  echo "Delegation count: $(jq '.app_state.staking.delegations | length' "$GENESIS_FILE")"
  echo "Validator tokens: $(jq -r '.app_state.staking.validators[0].tokens' "$GENESIS_FILE" 2>/dev/null || echo "N/A")"
  echo "Last total power: $(jq -r '.app_state.staking.last_total_power' "$GENESIS_FILE")"
  echo "Top-level validators array: $(jq '.validators | length' "$GENESIS_FILE")"
  echo "Genesis structure:"
  jq '{
    validators: (.validators | length),
    app_state: {
      staking: {
        validators: (.app_state.staking.validators | length),
        delegations: (.app_state.staking.delegations | length),
        last_total_power: .app_state.staking.last_total_power,
        last_validator_powers: (.app_state.staking.last_validator_powers | length)
      }
    }
  }' "$GENESIS_FILE"
  
  # Kiểm tra hợp lệ với wasmd
  wasmd genesis validate-genesis --home "$HOME_DIR" || {
    echo "❌ [ERROR] Genesis không hợp lệ theo wasmd validate-genesis!"
    exit 1
  }
  
  # Đảm bảo minimum-gas-prices đã được thiết lập trong app.toml
  echo "🔧 Kiểm tra lại cấu hình minimum-gas-prices trong app.toml..."
  sed -i 's/^minimum-gas-prices *=.*/minimum-gas-prices = "0.025stake"/' "$APP"
  if ! grep -q "^minimum-gas-prices" "$APP"; then
    echo "minimum-gas-prices = \"0.025stake\"" >> "$APP"
  fi
  echo "✅ Cấu hình minimum-gas-prices: $(grep "^minimum-gas-prices" "$APP")"
  
  # Xoá các thư mục cơ sở dữ liệu để tránh lỗi corruption
  if [ -d "$HOME_DIR/data" ]; then
    echo "📁 Sao lưu data hiện tại..."
    if [ ! -d "/tmp/data_backup" ]; then
      mkdir -p /tmp/data_backup
    fi
    
    # Backup timestamp
    BACKUP_TS=$(date +%s)
    
    # Cố gắng sao lưu nếu có thể
    cp -r "$HOME_DIR/data" "/tmp/data_backup/$BACKUP_TS" 2>/dev/null || echo "⚠️ Không thể sao lưu đầy đủ, tiếp tục..."
    
    # Xóa các database cũ an toàn
    echo "🗑️ Xoá các database cũ để tránh lỗi corruption..."
    safe_remove_dir "$HOME_DIR/data/application.db"
    safe_remove_dir "$HOME_DIR/data/blockstore.db"
    safe_remove_dir "$HOME_DIR/data/state.db"
    safe_remove_dir "$HOME_DIR/data/snapshots"
    safe_remove_dir "$HOME_DIR/data/tx_index.db"
    safe_remove_dir "$HOME_DIR/data/evidence.db"
    
    # Đảm bảo thư mục data tồn tại
    mkdir -p "$HOME_DIR/data"
  fi
  
  # Fix validator power if needed
  echo "🔧 Kiểm tra và sửa power của validator một lần cuối..."
  fix_validator_power "$GENESIS_FILE"
  
  # Print the final state of the genesis file for debugging
  echo "📋 Final genesis state before starting node:"
  jq '{
    validators: (.validators | length),
    app_state: {
      staking: {
        validators: (.app_state.staking.validators | length),
        delegations: (.app_state.staking.delegations | length),
        last_total_power: .app_state.staking.last_total_power,
        last_validator_powers: (.app_state.staking.last_validator_powers | length)
      }
    }
  }' "$GENESIS_FILE"
  
  # Copy genesis to a debug file for inspection if needed
  cp "$GENESIS_FILE" "/tmp/genesis_final_before_start.json"
  echo "📝 Final genesis saved to /tmp/genesis_final_before_start.json for inspection"

  # Khởi động node với output trực tiếp vào file log
  echo "🚀 Khởi động node với minimum-gas-prices=0.025stake..."
  wasmd start --home "$HOME_DIR" --minimum-gas-prices="0.025stake" --log_level debug --unsafe-skip-upgrades=1 > /tmp/logs/wasmd.log 2>&1 &
  NODE_PID=$!
  echo "🚀 Node đã khởi động với PID: $NODE_PID"

  # Chờ RPC sẵn sàng
  echo "⏳ Đợi node khởi động RPC..."
  TIMEOUT=180
  START_TIME=$(date +%s)
  NODE_STARTED=false
  
  while [ $(($(date +%s) - START_TIME)) -lt $TIMEOUT ]; do
    if curl -s http://localhost:26657/status >/dev/null 2>&1; then
      echo "✅ RPC endpoint đã hoạt động!"
      # Kiểm tra xem node đã catch-up chưa
      if curl -s http://localhost:26657/status | grep -q '"catching_up": false'; then
        NODE_STARTED=true
        echo "✅ Node đã đồng bộ xong (catching_up: false)"
        break
      else
        echo "⏳ Node đang trong quá trình đồng bộ..."
      fi
    fi
    sleep 3
    ELAPSED=$(($(date +%s) - START_TIME))
    REMAINING=$((TIMEOUT - ELAPSED))
    if [ $((ELAPSED % 10)) -eq 0 ]; then
      echo "⏳ Vẫn đang chờ node khởi động... ${REMAINING}s còn lại"
      # Kiểm tra tiến trình có còn chạy không
      if ! ps -p $NODE_PID > /dev/null; then
        echo "❌ [ERROR] Node process đã dừng hoạt động!"
        echo "⚠️ Xem 50 dòng log cuối cùng:"
        tail -n 50 /tmp/logs/wasmd.log
        break
      fi
    fi
  done
  
  if [ "$NODE_STARTED" = "false" ]; then
    echo "❌ [ERROR] Node không khởi động được trong $TIMEOUT giây."
    echo "⚠️ Kiểm tra trạng thái tiến trình:"
    ps -p $NODE_PID || echo "Node process không còn tồn tại"
    echo "⚠️ Xem logs của node (100 dòng cuối):"
    tail -n 100 /tmp/logs/wasmd.log 2>/dev/null || echo "Không tìm thấy log file."
    
    # Giữ container chạy để xem logs
    tail -f /tmp/logs/wasmd.log
    exit 1
  fi
  
  echo "✅ Node đã sẵn sàng để deploy hợp đồng"
  
  # Đợi thêm một chút để các nodes khác kết nối
  echo "⏳ Đợi thêm 15 giây để các nodes khác kết nối..."
  sleep 15

  # Kiểm tra trạng thái mạng
  echo "🔍 Kiểm tra trạng thái mạng..."
  curl -s http://localhost:26657/net_info | jq '.result.n_peers'
  
  # Kiểm tra xem file wasm tồn tại không
  if [ ! -f "/contracts/educhain.wasm" ]; then
    echo "❌ [ERROR] Không tìm thấy file contract tại /contracts/educhain.wasm"
    echo "⚠️ Liệt kê thư mục contracts:"
    ls -la /contracts/
    tail -f /tmp/logs/wasmd.log
    exit 1
  fi
  
  echo "📦 Upload contract..."
  UPLOAD_RESULT=$(wasmd tx wasm store /contracts/educhain.wasm \
    --from wallet --keyring-backend test --chain-id "$CHAIN_ID" --gas auto --gas-adjustment 1.3 --fees 5000stake -y -b block \
    --home "$HOME_DIR" 2>&1)
  echo "📋 Kết quả upload: $UPLOAD_RESULT"
  
  # Kiểm tra lỗi trong kết quả upload
  if echo "$UPLOAD_RESULT" | grep -q "ERROR"; then
    echo "❌ [ERROR] Lỗi khi upload contract:"
    echo "$UPLOAD_RESULT" | grep "ERROR"
    tail -f /tmp/logs/wasmd.log
    exit 1
  fi
  
  CODE_ID=$(echo "$UPLOAD_RESULT" | grep -A1 "code_id" | grep -o '[0-9]*')
  
  if [ -z "$CODE_ID" ]; then
    echo "❌ [ERROR] Không tìm thấy CODE_ID sau khi upload contract. Dừng việc instantiate."
    echo "📋 Output đầy đủ từ lệnh upload:"
    echo "$UPLOAD_RESULT"
    tail -f /tmp/logs/wasmd.log
    exit 1
  fi
  
  echo "🆔 CODE_ID: $CODE_ID"

  echo "🚀 Instantiate contract..."
  INST_RESULT=$(wasmd tx wasm instantiate "$CODE_ID" '{}' \
    --from wallet --label "educhain" \
    --admin "$WALLET_ADDRESS" \
    --keyring-backend test --chain-id "$CHAIN_ID" --gas auto --gas-adjustment 1.3 --fees 5000stake -y -b block \
    --home "$HOME_DIR" 2>&1)
  echo "📋 Kết quả instantiate: $INST_RESULT"
  
  # Kiểm tra lỗi trong kết quả instantiate
  if echo "$INST_RESULT" | grep -q "ERROR"; then
    echo "❌ [ERROR] Lỗi khi instantiate contract:"
    echo "$INST_RESULT" | grep "ERROR"
    tail -f /tmp/logs/wasmd.log
    exit 1
  fi
  
  CONTRACT_ADDR=$(echo "$INST_RESULT" | grep -A1 "contract_address" | grep -o 'wasm1[0-9a-z]*')
  
  if [ -z "$CONTRACT_ADDR" ]; then
    echo "❌ [ERROR] Không tìm thấy CONTRACT_ADDR sau khi instantiate contract."
    echo "📋 Output đầy đủ từ lệnh instantiate:"
    echo "$INST_RESULT"
    tail -f /tmp/logs/wasmd.log
    exit 1
  fi
  
  echo "🆔 CONTRACT_ADDR: $CONTRACT_ADDR"
  echo "✅ Đã khởi tạo contract tại: $CONTRACT_ADDR"
  
  # Thông tin tóm tắt
  echo "📋 Tóm tắt thông tin cài đặt thành công:"
  echo "- Validator address: $VAL_ADDRESS"
  echo "- Wallet address: $WALLET_ADDRESS"
  echo "- Node ID: $NODE_ID"
  echo "- Code ID: $CODE_ID"
  echo "- Contract address: $CONTRACT_ADDR"
  echo "APP path: $APP"

  # Đảm bảo minimum-gas-prices được thiết lập đúng một lần nữa trước khi kết thúc
  echo "🔧 Kiểm tra lại cấu hình minimum-gas-prices trong app.toml..."
  sed -i 's/^minimum-gas-prices *=.*/minimum-gas-prices = "0.025stake"/' "$APP"
  if ! grep -q "^minimum-gas-prices" "$APP"; then
    echo "minimum-gas-prices = \"0.025stake\"" >> "$APP"
  fi
  echo "✅ Cấu hình minimum-gas-prices: $(grep "^minimum-gas-prices" "$APP")"
  
  # Giữ container chạy
  tail -f /tmp/logs/wasmd.log
else
  echo "🚀 Khởi động node $MONIKER..."
  # Đảm bảo minimum-gas-prices được thiết lập đúng một lần nữa trước khi khởi động
  echo "🚀 Khởi động node $MONIKER..."
  # Đảm bảo minimum-gas-prices được thiết lập đúng một lần nữa trước khi khởi động
  echo "🔧 Kiểm tra lại cấu hình minimum-gas-prices trong app.toml..."
  sed -i 's/^minimum-gas-prices *=.*/minimum-gas-prices = "0.025stake"/' "$APP"
  if ! grep -q "^minimum-gas-prices" "$APP"; then
    echo "minimum-gas-prices = \"0.025stake\"" >> "$APP"
  fi
  echo "✅ Cấu hình minimum-gas-prices: $(grep "^minimum-gas-prices" "$APP")"
  
  # Kiểm tra hợp lệ với wasmd
  wasmd genesis validate-genesis --home "$HOME_DIR" || {
    echo "❌ [ERROR] Genesis không hợp lệ theo wasmd validate-genesis!"
    exit 1
  }
  
  # Xoá các thư mục cơ sở dữ liệu để tránh lỗi corruption
  if [ -d "$HOME_DIR/data" ]; then
    echo "📁 Sao lưu data hiện tại..."
    if [ ! -d "/tmp/data_backup" ]; then
      mkdir -p /tmp/data_backup
    fi
    
    # Backup timestamp
    BACKUP_TS=$(date +%s)
    
    # Cố gắng sao lưu nếu có thể
    cp -r "$HOME_DIR/data" "/tmp/data_backup/$BACKUP_TS" 2>/dev/null || echo "⚠️ Không thể sao lưu đầy đủ, tiếp tục..."
    
    # Xóa các database cũ an toàn
    echo "🗑️ Xoá các database cũ để tránh lỗi corruption..."
    safe_remove_dir "$HOME_DIR/data/application.db"
    safe_remove_dir "$HOME_DIR/data/blockstore.db"
    safe_remove_dir "$HOME_DIR/data/state.db"
    safe_remove_dir "$HOME_DIR/data/snapshots"
    safe_remove_dir "$HOME_DIR/data/tx_index.db"
    safe_remove_dir "$HOME_DIR/data/evidence.db"
    
    # Đảm bảo thư mục data tồn tại
    mkdir -p "$HOME_DIR/data"
  fi
  
  # DEBUG: Check genesis file content from the shared file
  echo "� DEBUG: Checking genesis.json content before startup..."
  echo "Validator count: $(jq '.app_state.staking.validators | length' "$GENESIS_FILE")"
  echo "Delegation count: $(jq '.app_state.staking.delegations | length' "$GENESIS_FILE")"
  echo "Validator tokens: $(jq -r '.app_state.staking.validators[0].tokens' "$GENESIS_FILE" 2>/dev/null || echo "N/A")"
  echo "Last total power: $(jq -r '.app_state.staking.last_total_power' "$GENESIS_FILE")"
  echo "Top-level validators array: $(jq '.validators | length' "$GENESIS_FILE")"
  
  # Copy genesis to a debug file for inspection if needed
  cp "$GENESIS_FILE" "/tmp/genesis_final_before_start_${MONIKER}.json"
  echo "📝 Final genesis saved to /tmp/genesis_final_before_start_${MONIKER}.json for inspection"
  
  # Khởi động node với mức gas tối thiểu được chỉ định rõ ràng
  echo "🚀 Khởi động node với minimum-gas-prices=0.025stake..."
  wasmd start --home "$HOME_DIR" --minimum-gas-prices="0.025stake" --log_level debug --unsafe-skip-upgrades=1
fi
