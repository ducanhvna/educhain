FROM rust:1.70 as builder

# Set the working directory
WORKDIR /usr/src/educhain

# Copy the Cargo.toml and Cargo.lock files
COPY contracts/educhain/Cargo.toml Cargo.lock ./

# Create a new directory for the source code
RUN mkdir src

# Copy the source code
COPY contracts/educhain/src ./src
COPY contracts/educhain/schema ./schema

# Build the project
RUN cargo build --release

# Use a smaller base image for the final image
FROM scratch

# Copy the compiled binary from the builder stage
COPY --from=builder /usr/src/educhain/target/release/educhain.wasm /educhain.wasm

# Set the entry point for the container
ENTRYPOINT ["/educhain.wasm"]