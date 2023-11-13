FROM rust:bookworm as builder

# Install deps (clang, llvm, sundials, cmake)
RUN apt-get update && apt-get install -y clang libclang-dev cmake llvm-14-dev llvm-14 libpolly-14-dev git
ENV LLVM_SYS_140_PREFIX /usr

# Build EnzymeAD
WORKDIR /usr/src
RUN git clone https://github.com/EnzymeAD/Enzyme
RUN mkdir -p Enzyme/build
WORKDIR /usr/src/Enzyme/build
RUN cmake -DLLVM_DIR=/usr/lib/llvm-14 -DCMAKE_BUILD_TYPE=Release ../enzyme 
RUN make

# emscripten
WORKDIR /usr/src
RUN git clone https://github.com/emscripten-core/emsdk.git 
WORKDIR /usr/src/emsdk
RUN git pull
RUN ./emsdk install latest
RUN ./emsdk activate latest
RUN source ./emsdk_env.sh

# Build openblas
WORKDIR /usr/src
RUN git clone https://github.com/OpenMathLib/OpenBLAS.git
WORKDIR /usr/src/OpenBLAS
RUN git checkout v0.3.24
RUN emmake make install libs shared CC=emcc HOSTCC=gcc TARGET=RISCV64_GENERIC NOFORTRAN=1 C_LAPACK=1 USE_THREAD=0 NO_SHARED=1 PREFIX=${EMSDK}/upstream/emscripten/cache/sysroot

# Build suite-sparse
WORKDIR /usr/src
RUN git clone https://github.com/martinjrobins/SuiteSparse.git
RUN mkdir SuiteSparse/build
WORKDIR /usr/src/SuiteSparse/build
RUN git checkout i424-build-shared-libs 
RUN emcmake cmake -DSUITESPARSE_ENABLE_PROJECTS=klu -DBUILD_SHARED_LIBS=OFF -DTARGET=generic -DNOPENMP=ON -DNPARTITION=ON -DNFORTRAN=ON -DBLA_STATIC=ON ..
RUN make install

WORKDIR /usr/src/app
COPY . .

# Build diffeq-runtime
RUN mkdir /usr/src/app/libs/diffeq-runtime/build
WORKDIR /usr/src/app/libs/diffeq-runtime/build
RUN emcmake cmake -DKLU_LIBRARY_DIR=${EMSDK}/upstream/emscripten/cache/sysroot/lib -DBUILD_SHARED_LIBS=OFF -DENABLE_KLU=ON -DTARGET=generic -DNOFORTRAN=1 -DNO_LAPACK=1 -DUSE_THREAD=0 ..
RUN make install

# Build diffeq-backend
WORKDIR /usr/src/app

# Will build and cache the binary and dependent crates in release mode
RUN --mount=type=cache,target=/usr/local/cargo,from=rust:latest,source=/usr/local/cargo \
    --mount=type=cache,target=target \
    cargo build --release && mv ./target/release/diffeq-backend ./diffeq-backend

# Runtime image
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y libffi8 libc6 git tar xz-utils lbzip2

# Run as "app" user
RUN useradd -ms /bin/bash app

USER app
WORKDIR /app

# Copy Emscripten SDK from builder, this will include openblas, suite-sparse, and diffeq-runtime
COPY --from=builder /usr/src/emsdk /app/emsdk

# Copy EnzymeAD from builder
RUN mkdir -p /app/lib
COPY --from=builder /usr/src/Enzyme/build/*.so /app/lib/

# Get compiled binaries from builder's cargo install directory
COPY --from=builder /usr/src/app/diffeq-backend /app/diffeq-backend

# Set LIBRARY_PATH to point to the wasm libs
ENV LIBRARY_PATH /app/lib
ENV PATH /app/emsdk:/app/emsdk/upstream/emscripten:${PATH}
ENV EMSDK /app/emsdk

# Run the app
CMD ./diffeq-backend