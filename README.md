# EduChain Project

EduChain is a blockchain-based project designed to facilitate educational transactions and interactions. This README provides an overview of the project structure, setup instructions, and usage guidelines.

## Project Structure

The project is organized as follows:

```
educhain/
├── contracts/
│   └── educhain/
│       ├── Cargo.toml          # Configuration file for the Rust package manager
│       ├── schema/
│       │   └── schema.rs       # Defines the schema for the smart contract
│       └── src/
│           ├── contract.rs      # Main logic of the smart contract
│           ├── lib.rs           # Library root for the smart contract
│           ├── msg.rs           # Defines messages for contract interactions
│           └── state.rs         # State structure of the smart contract
├── artifacts/
│   └── educhain.wasm           # Compiled WebAssembly binary of the smart contract
├── docker/
│   ├── Dockerfile               # Instructions for building the Docker image
│   ├── entrypoint.sh            # Entry point script for the Docker container
│   └── config/                  # Optional configuration files
│       ├── config.toml
│       ├── app.toml
│       └── genesis.json
├── generate.sh                  # Script to automate node creation and Docker setup
├── docker-compose.yml           # Defines services and networks for Docker containers
└── README.md                    # Documentation and instructions for the project
```

## Setup Instructions

1. **Clone the Repository**
   ```
   git clone <repository-url>
   cd educhain
   ```

2. **Build the Smart Contract**
   Navigate to the `contracts/educhain` directory and run:
   ```
   cargo build --release
   ```

3. **Build Docker Image**
   From the root of the project, build the Docker image:
   ```
   docker build -t educhain .
   ```

4. **Run the Application**
   Use Docker Compose to start the application:
   ```
   docker-compose up
   ```

## Usage

Once the application is running, you can interact with the smart contract through the defined entry points. Refer to the individual contract files for specific functions and their usage.

## Contributing

Contributions are welcome! Please submit a pull request or open an issue for any enhancements or bug fixes.

## License

This project is licensed under the MIT License. See the LICENSE file for more details.