FROM debian:bullseye

ARG GRPC_VERSION=1.36.0
ARG CMAKE_VERSION=3.19.6
ARG AWS_SDK_CPP_VERSION=1.8.155
ARG ZLIB_VERSION=1.2.11

RUN apt update && apt install -y git build-essential autoconf libtool pkg-config wget bash-completion vim gdb libgoogle-perftools-dev clang gcc curl ninja-build valgrind python3-pip

#install cmake-format
RUN pip3 install cmakelang

WORKDIR /tmp
RUN wget https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz
RUN tar xf cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz  -C /usr --strip-components=1

WORKDIR /build/zlib
RUN wget https://github.com/madler/zlib/archive/v${ZLIB_VERSION}.tar.gz
RUN tar xf v${ZLIB_VERSION}.tar.gz
WORKDIR /build/zlib/build
RUN cmake -GNinja -DBUILD_SHARED_LIBS=0 ../zlib-${ZLIB_VERSION}
RUN ninja
RUN ninja install

ARG OPENSSL_VERSION=1.1.1k
WORKDIR /build/openssl
RUN wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
RUN tar xf openssl-${OPENSSL_VERSION}.tar.gz
WORKDIR /build/openssl/build
RUN ../openssl-${OPENSSL_VERSION}/config
RUN make -j 8
RUN make install_sw



ARG CURL_VERSION=7_75_0
WORKDIR /build/curl
RUN wget https://github.com/curl/curl/archive/curl-${CURL_VERSION}.tar.gz
RUN tar xf curl-${CURL_VERSION}.tar.gz
WORKDIR /build/curl/build
RUN cmake -GNinja -DBUILD_SHARED_LIBS=0 ../curl-curl-${CURL_VERSION}
RUN ninja
RUN ninja install

WORKDIR /build/grpc

RUN git clone --recurse-submodules -b v${GRPC_VERSION} https://github.com/grpc/grpc
WORKDIR /build/grpc/build
RUN cmake -GNinja -DgRPC_ZLIB_PROVIDER=package -DgRPC_SSL_PROVIDER=package -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=RelWithDebInfo ../grpc
RUN ninja
RUN ninja install

WORKDIR /build/aws-sdk
RUN wget https://github.com/aws/aws-sdk-cpp/archive/${AWS_SDK_CPP_VERSION}.tar.gz
RUN tar xf ${AWS_SDK_CPP_VERSION}.tar.gz
WORKDIR /build/aws-sdk/build
RUN cmake -GNinja -DBUILD_ONLY="lambda;sns" -DBUILD_SHARED_LIBS=OFF -DENABLE_UNITY_BUILD=ON -DENABLE_TESTING=0 ../aws-sdk-cpp-${AWS_SDK_CPP_VERSION}
RUN ninja
RUN ninja install

ARG WOLFSSL_VERSION=master
WORKDIR /build/wolfssl
RUN wget https://github.com/wolfSSL/wolfssl/archive/refs/heads/master.zip
RUN unzip master.zip
WORKDIR /build/wolfssl/wolfssl-${WOLFSSL_VERSION}
RUN ./autogen.sh
# Fastest base intel config ./configure --enable-intelasm --enable-aesni --enable-fpecc --enable-fasthugemath --enable-sp-asm --enable-sp
# Test config modifications with ./wolfcrypt/benchmark/benchmark -ecc
#  Intel(R) Core(TM) i7-8550U results
#------------------------------------------------------------------------------
# wolfSSL version 4.7.1
#------------------------------------------------------------------------------
#wolfCrypt Benchmark (block bytes 1048576, min 1.0 sec each)
#ECDHE [      SECP256R1]   256 agree       53900 ops took 1.001 sec, avg 0.019 ms, 53859.332 ops/sec
#ECDSA [      SECP256R1]   256 sign        52300 ops took 1.000 sec, avg 0.019 ms, 52288.917 ops/sec
#ECDSA [      SECP256R1]   256 verify      46500 ops took 1.001 sec, avg 0.022 ms, 46475.512 ops/sec
#Benchmark complete
# in 4.7.0-stable there is a bug regarding --enable-fpecc in the benchmark on virtual machines so it has been disabled.
RUN ./configure --enable-aesni --enable-dtls  --enable-dtls-mtu --enable-sp --enable-sp-asm --enable-sp-math-all --enable-aesccm  --enable-intelasm --enable-aesni --enable-maxfragment --enable-fasthugemath --enable-harden --enable-static --disable-shared --enable-alpn  --enable-opensslcoexist --enable-sep --with-pic
RUN make -j 8
RUN ./wolfcrypt/benchmark/benchmark -ecc
RUN make install

RUN apt-get install sudo unzip -y

# Hiredis Install
WORKDIR /tmp
# TODO change to a tag when hiredis_static becomes a tagged thing (this is not the case in v1.0.2)
RUN wget https://github.com/redis/hiredis/archive/refs/heads/master.zip
RUN unzip master.zip
WORKDIR /tmp/hiredis-master/build
RUN cmake -GNinja -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_BUILD_TYPE=Release ..
RUN ninja && ninja install

# Abseil Install
WORKDIR /build/abseil
RUN curl -sSL https://github.com/abseil/abseil-cpp/archive/20211102.0.tar.gz | tar -xzf - --strip-components=1
RUN sed -i 's/^#define ABSL_OPTION_USE_\(.*\) 2/#define ABSL_OPTION_USE_\1 0/' "absl/base/options.h"
RUN cmake -DCMAKE_BUILD_TYPE=Release  -DBUILD_TESTING=OFF -DBUILD_SHARED_LIBS=yes -DCMAKE_CXX_STANDARD=11 -H. -Bcmake-out
RUN cmake --build cmake-out -- -j ${NCPU:-4}
RUN cmake --build cmake-out --target install -- -j ${NCPU:-4}
RUN ldconfig

# Crc32c Install
WORKDIR /build/crc32c
RUN curl -sSL https://github.com/google/crc32c/archive/1.1.2.tar.gz | tar -xzf - --strip-components=1
RUN cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=yes -DCRC32C_BUILD_TESTS=OFF -DCRC32C_BUILD_BENCHMARKS=OFF -DCRC32C_USE_GLOG=OFF -H. -Bcmake-out
RUN cmake --build cmake-out -- -j ${NCPU:-4}
RUN cmake --build cmake-out --target install -- -j ${NCPU:-4}
RUN ldconfig

# Nlohmann JSON Install
WORKDIR /build/nlohmann
RUN curl -sSL https://github.com/nlohmann/json/archive/v3.10.5.tar.gz | tar -xzf - --strip-components=1
RUN cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=yes -DBUILD_TESTING=OFF -DJSON_BuildTests=OFF -H. -Bcmake-out/nlohmann/json
RUN cmake --build cmake-out/nlohmann/json --target install -- -j ${NCPU:-4}
RUN ldconfig

# Protobuf Install
# Debian ships with 3.14, google-cloud-cpp requires 3.19 so we need this
WORKDIR /build/protobuf
RUN curl -sSL https://github.com/protocolbuffers/protobuf/archive/v3.19.3.tar.gz | tar -xzf - --strip-components=1
RUN cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=yes -Dprotobuf_BUILD_TESTS=OFF -Hcmake -Bcmake-out
RUN cmake --build cmake-out --target install -- -j ${NCPU:-4}
RUN ldconfig

# Google-cloud-cpp Install
ARG GCCPP_VERSION="v1.35.0"
WORKDIR /build/google-cloud-cpp
RUN wget -q https://github.com/googleapis/google-cloud-cpp/archive/${GCCPP_VERSION}.tar.gz
RUN tar -xf ${GCCPP_VERSION}.tar.gz -C /build/google-cloud-cpp --strip=1
RUN cmake -H. -Bcmake-out -DBUILD_TESTING=OFF -DGOOGLE_CLOUD_CPP_ENABLE_EXAMPLES=OFF -DGOOGLE_CLOUD_CPP_ENABLE=pubsub
RUN cmake --build cmake-out --target install

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create the user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME -s /bin/bash \
    #
    # [Optional] Add sudo support. Omit if you don't need to install software after connecting.
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

USER $USERNAME
WORKDIR /workspace/build
