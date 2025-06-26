#!/bin/bash
set -e

# Script đồng bộ genesis giữa các node Docker Compose
# Chạy script này từ thư mục gốc dự án

NODE1=educhain-node1-1
GENESIS_PATH_IN_CONTAINER="/root/.wasmd/config/genesis.json"
GENESIS_LOCAL="genesis_synced.json"

# 1. Khởi động node1 trước

echo "[1] Khởi động node1..."
docker-compose up -d node1

echo "[2] Đợi node1 tạo genesis.json..."
# Đợi file genesis.json xuất hiện trong container node1
while true; do
  docker exec $NODE1 test -f $GENESIS_PATH_IN_CONTAINER && break
  sleep 2
done
sleep 2

echo "[3] Copy genesis.json từ node1 ra host..."
docker cp $NODE1:$GENESIS_PATH_IN_CONTAINER $GENESIS_LOCAL

# 2. Copy genesis vào các node khác
for i in 2 3 4 5; do
  NODE=educhain-node${i}-1
  echo "[4] Copy genesis vào $NODE..."
  docker cp $GENESIS_LOCAL $NODE:$GENESIS_PATH_IN_CONTAINER || echo "Chưa có container $NODE, sẽ copy sau khi khởi động."
done

# 3. Khởi động các node còn lại
for i in 2 3 4 5; do
  NODE=educhain-node${i}-1
  echo "[5] Khởi động $NODE..."
  docker-compose up -d node$i
  # Copy lại genesis nếu cần
  sleep 2
  docker cp $GENESIS_LOCAL $NODE:$GENESIS_PATH_IN_CONTAINER || true
done

echo "[6] Xóa file genesis tạm trên host."
rm -f $GENESIS_LOCAL

echo "✅ Đã đồng bộ genesis và khởi động toàn bộ node!"
