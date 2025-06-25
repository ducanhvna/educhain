#!/bin/bash
set -e

MONIKER=${MONIKER:-"node1"}
CHAIN_ID="educhain-1"
HOME_DIR="/root/.wasmd"
CONFIG="$HOME_DIR/config/config.toml"
APP="$HOME_DIR/config/app.toml"
GENESIS_SHARED="/shared/genesis.json"

echo "🚀 Khởi động entrypoint cho $MONIKER"

# Khởi tạo node nếu chưa
if [ ! -f "$HOME_DIR/config/genesis.json" ]; then
  echo "🛠️ Khởi tạo node $MONIKER..."
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

# NODE1 tạo ví + genesis + gentx + chia sẻ genesis
if [ "$MONIKER" = "node1" ]; then
  echo "🔐 Tạo ví nếu chưa có..."
  if ! wasmd keys show wallet --home "$HOME_DIR" --keyring-backend test > /dev/null 2>&1; then
    wasmd keys add wallet --home "$HOME_DIR" --keyring-backend test
    wasmd add-genesis-account "$(wasmd keys show wallet -a --home "$HOME_DIR" --keyring-backend test)" 100000000stake --home "$HOME_DIR"
    wasmd gentx wallet 100000000stake --chain-id "$CHAIN_ID" --home "$HOME_DIR" --keyring-backend test
    wasmd collect-gentxs --home "$HOME_DIR"
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

# NODE1: upload và instantiate contract sau khi node khởi động
if [ "$MONIKER" = "node1" ]; then
  echo "🚦 Chờ node khởi động RPC..."
  wasmd start --home "$HOME_DIR" &

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
  wasmd start --home "$HOME_DIR"
fi
