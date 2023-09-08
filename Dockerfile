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
RUN apt-get update && apt-get install -y libsundials-dev libffi8 libc6

# Run as "app" user
RUN useradd -ms /bin/bash app

USER app
WORKDIR /app

# Get compiled binaries from builder's cargo install directory
COPY --from=builder /usr/src/app/diffeq-backend /app/diffeq-backend

# Copy libs
#RUN mkdir -p /usr/lib/x86_64-linux-gnu
#RUN mkdir -p /lib/x86_64-linux-gnu
#COPY --from=builder /lib/x86_64-linux-gnu/libffi*  /lib/x86_64-linux-gnu/
#COPY --from=builder /lib/x86_64-linux-gnu/libstdc++*  /lib/x86_64-linux-gnu/
#COPY --from=builder /lib/x86_64-linux-gnu/libgcc*  /lib/x86_64-linux-gnu/
#COPY --from=builder /lib/x86_64-linux-gnu/libc*  /lib/x86_64-linux-gnu/
#COPY --from=builder /usr/lib/x86_64-linux-gnu/libsundials*  /usr/lib/x86_64-linux-gnu/

# Get wasm libs from host machine (remember to build them first!)
COPY ./libs/lib /app/lib

# Set LIBRARY_PATH to point to the wasm libs
ENV LIBRARY_PATH /app/lib
ENV LD_LIBRARY_PATH /usr/lib/x86_64-linux-gnu

# Run the app
CMD ./diffeq-backend