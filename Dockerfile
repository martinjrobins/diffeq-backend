FROM rust:latest as builder

WORKDIR /usr/src/app
COPY . .

# Will build and cache the binary and dependent crates in release mode
RUN --mount=type=cache,target=/usr/local/cargo,from=rust:latest,source=/usr/local/cargo \
    --mount=type=cache,target=target \
    cargo build --release && mv ./target/release/diffeq-backend ./diffeq-backend

# Runtime image
FROM debian:bullseye-slim

# Run as "app" user
RUN useradd -ms /bin/bash app

USER app
WORKDIR /app

# Get compiled binaries from builder's cargo install directory
COPY --from=builder /usr/src/app/diffeq-backend /app/diffeq-backend

# Get wasm libs from host machine (remember to build them first!)
COPY ./libs/lib /app/lib

# Set LIBRARY_PATH to point to the wasm libs
ENV LIBRARY_PATH /app/lib

# Run the app
CMD ./diffeq-backend