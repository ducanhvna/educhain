#!/bin/sh
set -e

# Nếu có tham số truyền vào là lệnh CLI thì exec trực tiếp và thoát
if [ $# -gt 0 ]; then
  exec "$@"
fi

MONIKER=${MONIKER:-"node1"}
CHAIN_ID="educhain-1"
HOME_DIR="/root/.wasmd"
CONFIG="$HOME_DIR/config/config.toml"
APP="$HOME_DIR/config/app.toml"
GENESIS_SHARED="/shared/genesis.json"

# Xóa genesis.json mẫu nếu có (chỉ node1 mới init)
if [ "$MONIKER" = "node1" ]; then
  if [ -f "$HOME_DIR/config/genesis.json" ]; then
    echo "⚠️ Xóa genesis.json mẫu cũ để init lại từ đầu..."
    rm -f "$HOME_DIR/config/genesis.json"
  fi
fi

echo "🚀 Khởi động entrypoint cho $MONIKER"

# Khởi tạo node nếu chưa hoặc genesis.json rỗng
if [ ! -s "$HOME_DIR/config/genesis.json" ]; then
  echo "⚠️ genesis.json bị thiếu hoặc rỗng. Khởi tạo lại..."
  wasmd init "$MONIKER" --chain-id "$CHAIN_ID" --home "$HOME_DIR"
fi

# Cấu hình RPC và P2P
sed -i "s/^moniker *=.*/moniker = \"$MONIKER\"/" "$CONFIG"
sed -i "s/^rpc.laddr *=.*/rpc.laddr = \"tcp:\/\/0.0.0.0:26657\"/" "$CONFIG"
sed -i "s/^laddr *=.*/laddr = \"tcp:\/\/0.0.0.0:26656\"/" "$CONFIG"

# Thiết lập persistent_peers nếu có
if [ -n "$PEERS" ]; then
  echo "🔗 Cấu hình peer: $PEERS"
  sed -i "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" "$CONFIG"
fi

# Fix pruning & gas config for Cosmos SDK >=0.47 (remove deprecated keys, enforce [app] section)
# Remove all old pruning keys/sections
sed -i '/^pruning-interval/d' "$CONFIG"
sed -i '/^pruning-keep-recent/d' "$CONFIG"
sed -i '/^pruning-interval/d' "$APP"
sed -i '/^pruning-keep-recent/d' "$APP"
sed -i '/^minimum-gas-prices/d' "$APP"
sed -i '/^pruning *=/d' "$APP"
sed -i '/^\[pruning\]/d' "$APP"
# Remove duplicate [app] sections, keep only the first
awk 'BEGIN{s=0} /^\[app\]/{if(s++)next} 1' "$APP" > "$APP.tmp" && mv "$APP.tmp" "$APP"
# Ensure [app] is at the top, and only one [app] section
awk 'BEGIN{a=0} /^\[app\]/{a=1} a && !/^\[app\]/{exit} {print}' "$APP" > "$APP.tmp" && mv "$APP.tmp" "$APP"

# Đảm bảo [app] là section đầu tiên, không có dòng nào trước nó
if [ -f "$APP" ]; then
  awk 'BEGIN{found=0} /^\[app\]/{found=1} found{print > "/tmp/app_block"; next} {print > "/tmp/app_rest"}' "$APP"
  cat /tmp/app_block /tmp/app_rest > "$APP"
  rm -f /tmp/app_block /tmp/app_rest
fi

# Chỉ thay giá trị minimum-gas-prices nếu đã có, nếu chưa có thì thêm ngay sau [app]
if [ -f "$APP" ]; then
  if grep -q '^minimum-gas-prices' "$APP"; then
    sed -i 's/^minimum-gas-prices *=.*/minimum-gas-prices = "0.025stake"/' "$APP"
  else
    awk 'BEGIN{done=0} /^\[app\]/{print; print "minimum-gas-prices = \"0.025stake\""; done=1; next} {print}' "$APP" > "$APP.tmp" && mv "$APP.tmp" "$APP"
  fi
  sed -i '1s/^\xEF\xBB\xBF//' "$APP"
fi
cat "$APP"

# XÓA HOÀN TOÀN block ghi đè [app] phía dưới để tránh lặp section và xung đột cấu hình

# Đồng bộ genesis giữa các node
if [ "$MONIKER" = "node1" ]; then
  echo "🔐 Tạo ví nếu chưa có..."
  if ! wasmd keys show wallet --home "$HOME_DIR" --keyring-backend test > /dev/null 2>&1; then
    wasmd keys add wallet --home "$HOME_DIR" --keyring-backend test
  fi
  ADDRESS=$(wasmd keys show wallet -a --home "$HOME_DIR" --keyring-backend test | head -n 1 | tr -d '\r\n')
  echo "Địa chỉ ví wallet: >$ADDRESS<"
  echo "[DEBUG] Lệnh add-genesis-account: wasmd genesis add-genesis-account $ADDRESS 2000000000000stake --home $HOME_DIR --keyring-backend test"
  wasmd genesis add-genesis-account "$ADDRESS" 2000000000000stake --home "$HOME_DIR" --keyring-backend test || { echo '[ERROR] Lệnh add-genesis-account thất bại'; exit 1; }
  # Làm sạch genesis.json sau add-genesis-account
  GENESIS_FILE="$HOME_DIR/config/genesis.json"
  if [ -f "$GENESIS_FILE" ]; then
    # Xóa hoàn toàn gov.params, sau đó tạo lại object params hợp lệ
    jq 'if .app_state.gov then .app_state.gov |= (del(.params) | del(.deposit_params) | del(.voting_params) | del(.tally_params)) | .params = {
      min_deposit: [{"amount":"10000000","denom":"stake"}],
      max_deposit_period: "172800s",
      voting_period: "172800s",
      quorum: "0.334000000000000000",
      threshold: "0.500000000000000000",
      veto_threshold: "0.334000000000000000",
      burn_vote_quorum: false,
      burn_vote_veto: true,
      burn_proposal_deposit_prevote: false,
      min_initial_deposit_ratio: "0.000000000000000000"
    } else . end' "$GENESIS_FILE" | sponge "$GENESIS_FILE"
  fi

  # Start node ở background để gửi tx create-validator
  echo "🚦 Khởi động node background để gửi create-validator..."
  wasmd start --home "$HOME_DIR" --minimum-gas-prices="0.025stake" &
  NODE_PID=$!
  # Chờ RPC sẵn sàng
  until curl -s http://localhost:26657/status | grep -q '"catching_up": false'; do
    sleep 2
  done
  echo "✅ Node background đã sẵn sàng, gửi create-validator..."

  wasmd tx staking create-validator \
    --amount 2000000000000stake \
    --pubkey "$VAL_PUBKEY" \
    --moniker "$MONIKER" \
    --chain-id "$CHAIN_ID" \
    --commission-rate "0.10" \
    --commission-max-rate "0.20" \
    --commission-max-change-rate "0.01" \
    --min-self-delegation "1" \
    --from wallet \
    --keyring-backend test \
    --home "$HOME_DIR" \
    --yes \
    --gas auto \
    --fees 5000stake \
    -b block

  # Làm sạch genesis.json sau create-validator (trước collect-gentxs)
  if [ -f "$GENESIS_FILE" ]; then
    jq 'if .app_state.gov then .app_state.gov |= (del(.params) | del(.deposit_params) | del(.voting_params) | del(.tally_params)) | .params = {
      min_deposit: [{"amount":"10000000","denom":"stake"}],
      max_deposit_period: "172800s",
      voting_period: "172800s",
      quorum: "0.334000000000000000",
      threshold: "0.500000000000000000",
      veto_threshold: "0.334000000000000000",
      burn_vote_quorum: false,
      burn_vote_veto: true,
      burn_proposal_deposit_prevote: false,
      min_initial_deposit_ratio: "0.000000000000000000"
    } else . end' "$GENESIS_FILE" | sponge "$GENESIS_FILE"
  fi

  # Stop node background
  echo "🛑 Dừng node background sau khi gửi create-validator..."
  kill $NODE_PID
  sleep 3

  wasmd collect-gentxs --home "$HOME_DIR"
  # Làm sạch genesis.json lần nữa sau collect-gentxs
  if [ -f "$GENESIS_FILE" ]; then
    jq 'if .app_state.gov then .app_state.gov |= (del(.params) | del(.deposit_params) | del(.voting_params) | del(.tally_params)) | .params = {
      min_deposit: [{"amount":"10000000","denom":"stake"}],
      max_deposit_period: "172800s",
      voting_period: "172800s",
      quorum: "0.334000000000000000",
      threshold: "0.500000000000000000",
      veto_threshold: "0.334000000000000000",
      burn_vote_quorum: false,
      burn_vote_veto: true,
      burn_proposal_deposit_prevote: false,
      min_initial_deposit_ratio: "0.000000000000000000"
    } else . end' "$GENESIS_FILE" | sponge "$GENESIS_FILE"
  fi

  echo "📤 Chia sẻ genesis.json đến volume chung..."
  cp "$HOME_DIR/config/genesis.json" "$GENESIS_SHARED"
else
  echo "⏳ Đợi genesis.json từ node1..."
  until [ -f "$GENESIS_SHARED" ]; do
    sleep 1
  done
  echo "📥 Nhận genesis.json cho $MONIKER"
  cp "$GENESIS_SHARED" "$HOME_DIR/config/genesis.json"
fi

# Khởi động node và upload contract nếu là node1
if [ "$MONIKER" = "node1" ]; then
  echo "🚦 Chờ node khởi động RPC..."
  wasmd start --home "$HOME_DIR" --minimum-gas-prices="0.025stake" &

  until curl -s http://localhost:26657/status | grep -q '"catching_up": false'; do
    sleep 2
  done
  echo "✅ Node đã sẵn sàng để deploy hợp đồng"

  echo "🚀 Upload contract..."
  CODE_ID=$(wasmd tx wasm store /contracts/educhain.wasm \
    --from wallet --keyring-backend test --chain-id "$CHAIN_ID" --gas auto --fees 5000stake -y -b block \
    --home "$HOME_DIR" | grep -A1 "code_id" | grep -o '[0-9]*')

  echo "📦 Instantiate contract..."
  CONTRACT_ADDR=$(wasmd tx wasm instantiate "$CODE_ID" '{}' \
    --from wallet --label "educhain" \
    --admin "$(wasmd keys show wallet -a --keyring-backend test --home "$HOME_DIR")" \
    --keyring-backend test --chain-id "$CHAIN_ID" -y -b block \
    --home "$HOME_DIR" | grep -A1 "contract_address" | grep -o 'wasm1[0-9a-z]*')

  echo "✅ Đã khởi tạo contract tại: $CONTRACT_ADDR"

  # Giữ container chạy
  tail -f /dev/null
else
  echo "🚀 Khởi động node $MONIKER..."
  wasmd start --home "$HOME_DIR" --minimum-gas-prices="0.025stake"
fi
