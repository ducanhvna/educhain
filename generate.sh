#!/bin/bash

# This script automates the creation of 5 nodes and generates the docker-compose.yml file.

# Function to create a node
create_node() {
  NODE_NAME="node$1"
  echo "Creating $NODE_NAME..."
  # Here you would add the commands to create a node
}

# Create 5 nodes
for i in {1..5}
do
  create_node $i
done

# Generate docker-compose.yml
echo "Generating docker-compose.yml..."
cat <<EOL > docker-compose.yml
version: '3.8'

services:
EOL

for i in {1..5}
do
  echo "  node$i:" >> docker-compose.yml
  echo "    image: educhain-node" >> docker-compose.yml
  echo "    ports:" >> docker-compose.yml
  echo "      - \"$(expr 3000 + $i):3000\"" >> docker-compose.yml
  echo "    networks:" >> docker-compose.yml
  echo "      - educhain-network" >> docker-compose.yml
done

cat <<EOL >> docker-compose.yml
networks:
  educhain-network:
    driver: bridge
EOL

echo "docker-compose.yml generated successfully."