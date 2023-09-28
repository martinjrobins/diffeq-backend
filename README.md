# Installation

## Install diffeq-runtime

Remember to init and update submodules (if you haven't already)

```bash
git submodule init
git submodule update
```

Then, create a build dir

```bash
cd libs/diffeq-runtime
mkdir build
```

Then, set your environment using emsdk

```bash
source /path/to/emsdk/emsdk_env.sh
```

Then, configure

```bash
emcmake cmake -DCMAKE_INSTALL_PREFIX=../../ -DCMAKE_BUILD_TYPE=Release ..
```


Then, build and install

```bash
make install
```

This should put the runtime in `libs/lib`, and the headers in `libs/include`.


## Deploy

```bash
fly deploy
```