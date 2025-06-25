#!/bin/bash
set -e

CHAIN_ID="localnet"
NODES=5
BASE_PORT=26650
PEER_LIST=()
VERSION="v0.45.0"  # Có thể đổi sang phiên bản mới hơn nếu cần
GO_VERSION="1.21.0"

echo "🚀 Kiểm tra Go..."
if ! command -v go &> /dev/null; then
  echo "⚠️ Go chưa được cài. Đang cài Go $GO_VERSION..."
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="amd64"
  if [[ "$OS" == "darwin" ]]; then
    GO_FILE="go$GO_VERSION.darwin-$ARCH.tar.gz"
  else
    GO_FILE="go$GO_VERSION.linux-$ARCH.tar.gz"
  fi
  wget https://go.dev/dl/$GO_FILE
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf $GO_FILE
  export PATH=$PATH:/usr/local/go/bin
  echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
fi

echo "✅ Go version: $(go version)"

echo "📦 Cloning wasmd $VERSION..."
if [ ! -d "wasmd" ]; then
  git clone https://github.com/CosmWasm/wasmd.git
fi
cd wasmd
git fetch --all
git checkout $VERSION

echo "🔨 Building wasmd..."
make install

echo "✅ wasmd đã được cài tại: $(which wasmd)"
echo "🧪 Kiểm tra: wasmd version → $(wasmd version)"

echo "🚀 Khởi tạo $NODES node Cosmos..."

for i in $(seq 1 $NODES); do
  MONIKER="node$i"
  DIR="./data/$MONIKER"
  PORT=$((BASE_PORT + i * 10))

  echo "📦 Tạo thư mục $DIR"
  rm -rf $DIR && mkdir -p $DIR

  wasmd init $MONIKER --chain-id $CHAIN_ID --home $DIR > /dev/null

  NODE_ID=$(wasmd tendermint show-node-id --home $DIR)
  PEER_LIST+=("$NODE_ID@$MONIKER:$PORT")
done

# Tạo genesis từ node1
cp ./data/node1/config/genesis.json ./genesis.json

# Copy genesis sang các node khác
for i in $(seq 2 $NODES); do
  cp ./genesis.json ./data/node$i/config/genesis.json
done

# Tạo docker-compose.yml
echo "🛠️ Tạo docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: "3.8"
services:
EOF

for i in $(seq 1 $NODES); do
  MONIKER="node$i"
  PORT=$((BASE_PORT + i * 10))
  PEERS=$(IFS=, ; echo "${PEER_LIST[*]/$MONIKER@/}") # Loại bỏ chính nó

  cat >> docker-compose.yml <<EOF
  $MONIKER:
    image: cosmwasm/wasmd:latest
    container_name: $MONIKER
    ports:
      - "$((PORT+7)):$((PORT+7))"
    volumes:
      - ./data/$MONIKER:/root/.wasmd
    environment:
      - MONIKER=$MONIKER
      - PEERS=$PEERS
    command: wasmd start
EOF
done

echo "✅ Đã tạo docker-compose.yml và cấu hình node!"

echo "👉 Giờ Anh chỉ cần chạy:"
echo ""
echo "   docker compose up"
echo ""
