FROM rust:latest as builder

# Install deps (clang, llvm, sundials, cmake)
RUN apt-get update && apt-get install -y clang libclang-dev libsundials-dev cmake llvm-14-dev llvm-14 libpolly-14-dev
ENV LLVM_SYS_140_PREFIX /usr

WORKDIR /usr/src/app
COPY . .

# Will build and cache the binary and dependent crates in release mode
RUN --mount=type=cache,target=/usr/local/cargo,from=rust:latest,source=/usr/local/cargo \
    --mount=type=cache,target=target \
    cargo build --release && mv ./target/release/diffeq-backend ./diffeq-backend

# Runtime image
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y libsundials-dev libffi8 libc6 git tar xz-utils lbzip2

# Run as "app" user
RUN useradd -ms /bin/bash app

USER app
WORKDIR /app

# emscripten
RUN git clone https://github.com/emscripten-core/emsdk.git 
WORKDIR /app/emsdk
RUN git pull
RUN ./emsdk install latest
RUN ./emsdk activate latest

WORKDIR /app

# Get compiled binaries from builder's cargo install directory
COPY --from=builder /usr/src/app/diffeq-backend /app/diffeq-backend

# Get wasm libs from host machine (remember to build them first!)
COPY ./libs/lib /app/lib

# Set LIBRARY_PATH to point to the wasm libs
ENV LIBRARY_PATH /app/lib
ENV PATH /app/emsdk:/app/emsdk/upstream/emscripten:${PATH}
ENV EMSDK /app/emsdk

# Run the app
CMD ./diffeq-backend