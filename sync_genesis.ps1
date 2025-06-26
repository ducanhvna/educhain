# PowerShell script to sync genesis.json between docker nodes
# Run this from the project root

$ErrorActionPreference = 'Stop'

# Tìm tên container node1 thực tế
$NODE1 = $(docker ps -a --format '{{.Names}}' | Where-Object { $_ -like 'educhain-node1*' } | Select-Object -First 1)
if (-not $NODE1) {
    Write-Host "Không tìm thấy container node1. Hãy chắc chắn đã chạy docker-compose up -d node1 trước!" -ForegroundColor Red
    exit 1
}

$GENESIS_PATH_IN_CONTAINER = "/root/.wasmd/config/genesis.json"
$GENESIS_LOCAL = "genesis_synced.json"

Write-Host "[1] Khởi động node1..."
docker-compose up -d node1

Write-Host "[2] Đợi node1 tạo genesis.json..."
while ($true) {
    $exists = docker exec $NODE1 test -f $GENESIS_PATH_IN_CONTAINER; if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 2
}
Start-Sleep -Seconds 2

Write-Host "[3] Copy genesis.json từ node1 ra host..."
docker cp "$NODE1`:$GENESIS_PATH_IN_CONTAINER" $GENESIS_LOCAL

# 2. Copy genesis vào các node khác
foreach ($i in 2..5) {
    $NODE = "educhain-node$($i)-1"
    Write-Host "[4] Copy genesis vào $NODE..."
    try {
        docker cp $GENESIS_LOCAL "$NODE`:$GENESIS_PATH_IN_CONTAINER"
    } catch {
        Write-Host "Chưa có container $NODE, sẽ copy sau khi khởi động."
    }
}

# 3. Khởi động các node còn lại
foreach ($i in 2..5) {
    $NODE = "educhain-node$($i)-1"
    Write-Host "[5] Khởi động $NODE..."
    docker-compose up -d "node$i"
    Start-Sleep -Seconds 2
    try {
        docker cp $GENESIS_LOCAL "$NODE`:$GENESIS_PATH_IN_CONTAINER"
    } catch {}
}

Write-Host "[6] Xóa file genesis tạm trên host."
Remove-Item $GENESIS_LOCAL -ErrorAction SilentlyContinue

Write-Host "Da dong bo genesis va khoi dong toan bo node!"
