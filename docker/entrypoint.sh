#!/bin/bash
set -e

MONIKER=${MONIKER:-"node1"}
CHAIN_ID="localnet"
CONFIG="/root/.wasmd/config/config.toml"
APP="/root/.wasmd/config/app.toml"

# Cấu hình động nếu cần
sed -i "s/^moniker *=.*/moniker = \"$MONIKER\"/" $CONFIG
sed -i "s/^rpc.laddr *=.*/rpc.laddr = \"tcp:\/\/0.0.0.0:26657\"/" $CONFIG
sed -i "s/^laddr *=.*/laddr = \"tcp:\/\/0.0.0.0:26656\"/" $CONFIG

# Khởi động node ở nền
wasmd start &

# Chờ node sẵn sàng
echo "⏳ Đợi node $MONIKER khởi động..."
until curl -s http://localhost:26657/status | grep -q '"catching_up": false'; do
  sleep 2
done
echo "✅ Node $MONIKER sẵn sàng"

# Tạo ví và deploy contract nếu là node khởi tạo
if [ "$MONIKER" = "node1" ]; then
  echo "📦 Tạo ví nếu chưa có..."
  if ! wasmd keys show wallet --keyring-backend test > /dev/null 2>&1; then
    wasmd keys add wallet --keyring-backend test
    wasmd add-genesis-account $(wasmd keys show wallet -a --keyring-backend test) 100000000stake
    wasmd gentx wallet 100000000stake --chain-id $CHAIN_ID --keyring-backend test
    wasmd collect-gentxs
  fi

  echo "🚀 Uploading contract..."
  CODE_ID=$(wasmd tx wasm store /contracts/educhain.wasm \
    --from wallet --keyring-backend test --chain-id $CHAIN_ID --gas auto --fees 5000stake -y -b block \
    | grep -A1 "code_id" | grep -o '[0-9]*')

  echo "📥 Instantiate contract..."
  ADDR=$(wasmd tx wasm instantiate $CODE_ID '{}' \
    --from wallet --label "educhain" --admin $(wasmd keys show wallet -a --keyring-backend test) \
    --keyring-backend test --chain-id $CHAIN_ID -y -b block \
    | grep -A1 "contract_address" | grep -o 'wasm1[0-9a-z]*')

  echo "✅ Contract đã khởi tạo tại địa chỉ: $ADDR"
fi

# Giữ container chạy
tail -f /dev/null
