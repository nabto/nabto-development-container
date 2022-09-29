FROM debian:bullseye AS base
ARG CMAKE_VERSION=3.19.6

RUN apt update && apt install -y git build-essential autoconf libtool pkg-config wget bash-completion vim gdb libgoogle-perftools-dev clang gcc curl ninja-build valgrind python3-pip sudo unzip cmake-format

WORKDIR /tmp
RUN wget https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz
RUN tar xf cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz  -C /usr --strip-components=1

FROM base as zlib
ARG ZLIB_VERSION=1.2.11

WORKDIR /build/zlib
RUN wget https://github.com/madler/zlib/archive/v${ZLIB_VERSION}.tar.gz
RUN tar xf v${ZLIB_VERSION}.tar.gz
WORKDIR /build/zlib/build
RUN cmake -GNinja -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=0 ../zlib-${ZLIB_VERSION}
RUN ninja
RUN ninja install

FROM base as openssl
ARG OPENSSL_VERSION=1.1.1k

WORKDIR /build/openssl
RUN wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
RUN tar xf openssl-${OPENSSL_VERSION}.tar.gz
WORKDIR /build/openssl/build
RUN ../openssl-${OPENSSL_VERSION}/config
RUN make -j 8
RUN make install_sw

FROM base as curl
COPY --from=openssl /usr/local /usr/local
ARG CURL_VERSION=7_75_0
WORKDIR /build/curl
RUN wget https://github.com/curl/curl/archive/curl-${CURL_VERSION}.tar.gz
RUN tar xf curl-${CURL_VERSION}.tar.gz
WORKDIR /build/curl/build
RUN cmake -GNinja -DBUILD_SHARED_LIBS=0 -DCMAKE_POSITION_INDEPENDENT_CODE=ON ../curl-curl-${CURL_VERSION}
RUN ninja
RUN ninja install

FROM base as cares
ARG CARES_VERSION=1_18_1
WORKDIR /build/cares
RUN wget https://github.com/c-ares/c-ares/archive/refs/tags/cares-${CARES_VERSION}.tar.gz
RUN tar xf cares-${CARES_VERSION}.tar.gz
WORKDIR /build/cares/build
RUN cmake .. -GNinja -DBUILD_SHARED_LIBS=OFF -DCARES_STATIC=ON -DCARES_SHARED=OFF -DCARES_STATIC_PIC=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON ../c-ares-cares-${CARES_VERSION}
RUN ninja install

FROM base as re2
ARG RE2_VERSION=2022-06-01
WORKDIR /build/src
RUN curl -sSL https://github.com/google/re2/archive/refs/tags/${RE2_VERSION}.tar.gz | tar -xzf - --strip-components=1
WORKDIR /build/build
RUN cmake .. -GNinja -DBUILD_SHARED_LIBS=0 -DCMAKE_POSITION_INDEPENDENT_CODE=ON ../src
RUN ninja install

FROM base as protobuf

WORKDIR /build/src
ARG PROTOBUF_VERSION=21.2
RUN curl -sSL https://github.com/protocolbuffers/protobuf/archive/v${PROTOBUF_VERSION}.tar.gz | tar -xzf - --strip-components=1
WORKDIR /build/build
RUN cmake -GNinja -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -Dprotobuf_BUILD_TESTS=OFF ../src
RUN ninja install
RUN ldconfig

FROM base as abseil
# Abseil Install
WORKDIR /build/abseil
RUN curl -sSL https://github.com/abseil/abseil-cpp/archive/20211102.0.tar.gz | tar -xzf - --strip-components=1
RUN sed -i 's/^#define ABSL_OPTION_USE_\(.*\) 2/#define ABSL_OPTION_USE_\1 0/' "absl/base/options.h"
RUN cmake -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_BUILD_TYPE=Release  -DBUILD_TESTING=OFF -DBUILD_SHARED_LIBS=OFF -DCMAKE_CXX_STANDARD=11 -H. -Bcmake-out
RUN cmake --build cmake-out -- -j ${NCPU:-4}
RUN cmake --build cmake-out --target install -- -j ${NCPU:-4}
RUN ldconfig


FROM base as grpc
ARG GRPC_VERSION=1.47.0

COPY --from=zlib /usr/local /usr/local
COPY --from=cares /usr/local /usr/local
COPY --from=re2 /usr/local /usr/local
COPY --from=openssl /usr/local /usr/local
COPY --from=protobuf /usr/local /usr/local
COPY --from=abseil /usr/local /usr/local
RUN ldconfig

WORKDIR /build/src
RUN curl -sSL https://github.com/grpc/grpc/archive/refs/tags/v${GRPC_VERSION}.tar.gz | tar -xzf - --strip-components=1
WORKDIR /build/build
RUN cmake -GNinja -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DgRPC_ZLIB_PROVIDER=package -DgRPC_SSL_PROVIDER=package -DgRPC_RE2_PROVIDER=package -DgRPC_PROTOBUF_PROVIDER=package -DgRPC_ABSL_PROVIDER=package -DgRPC_CARES_PROVIDER=package  -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=RelWithDebInfo ../src
RUN ninja
RUN ninja install

FROM base as aws_sdk
ARG AWS_SDK_CPP_VERSION=1.8.155
COPY --from=curl /usr/local /usr/local

WORKDIR /build/aws-sdk
RUN wget https://github.com/aws/aws-sdk-cpp/archive/${AWS_SDK_CPP_VERSION}.tar.gz
RUN tar xf ${AWS_SDK_CPP_VERSION}.tar.gz
WORKDIR /build/aws-sdk/build
RUN cmake -GNinja -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_ONLY="lambda;sns" -DBUILD_SHARED_LIBS=OFF -DENABLE_UNITY_BUILD=ON -DENABLE_TESTING=0 ../aws-sdk-cpp-${AWS_SDK_CPP_VERSION}
RUN ninja
RUN ninja install

FROM base as wolfssl
WORKDIR /build/wolfssl
RUN curl -sSL https://github.com/wolfSSL/wolfssl/archive/refs/tags/v5.5.1-stable.tar.gz | tar -xzf - --strip-components=1
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
RUN ./configure --enable-aesni --enable-dtls  --enable-dtls-mtu --enable-sp --enable-sp-asm --enable-sp-math-all --enable-aesccm  --enable-intelasm --enable-aesni --enable-maxfragment --enable-fasthugemath --enable-harden --enable-static --disable-shared --enable-alpn  --enable-opensslcoexist --enable-sep --with-pic --enable-certgen --enable-keygen --enable-sni CFLAGS="-DKEEP_PEER_CERT  -DWOLFSSL_PUBLIC_MP -DWOLFSSL_PUBLIC_ECC_ADD_DBL"
RUN make -j 8
RUN ./wolfcrypt/benchmark/benchmark -ecc
RUN make install

FROM base as hiredis
COPY --from=openssl /usr/local /usr/local
# Hiredis Install
WORKDIR /tmp
# TODO change to a tag when hiredis_static becomes a tagged thing (this is not the case in v1.0.2)
RUN wget https://github.com/redis/hiredis/archive/refs/heads/master.zip
RUN unzip master.zip
WORKDIR /tmp/hiredis-master/build
RUN cmake -GNinja  -DBUILD_SHARED_LIBS=0 -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_BUILD_TYPE=Release ..
RUN ninja && ninja install


FROM base as crc32
# Crc32c Install
WORKDIR /build/crc32c
RUN curl -sSL https://github.com/google/crc32c/archive/1.1.2.tar.gz | tar -xzf - --strip-components=1
RUN cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=0 -DCRC32C_BUILD_TESTS=OFF -DCRC32C_BUILD_BENCHMARKS=OFF -DCRC32C_USE_GLOG=OFF -H. -Bcmake-out
RUN cmake --build cmake-out -- -j ${NCPU:-4}
RUN cmake --build cmake-out --target install -- -j ${NCPU:-4}
RUN ldconfig

FROM base as nlohmann_json
# Nlohmann JSON Install
WORKDIR /build/nlohmann
RUN curl -sSL https://github.com/nlohmann/json/archive/v3.10.5.tar.gz | tar -xzf - --strip-components=1
RUN cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=0 -DBUILD_TESTING=OFF -DJSON_BuildTests=OFF -H. -Bcmake-out/nlohmann/json
RUN cmake --build cmake-out/nlohmann/json --target install -- -j ${NCPU:-4}
RUN ldconfig

FROM base as google_sdk
COPY --from=curl /usr/local /usr/local
COPY --from=abseil /usr/local /usr/local
COPY --from=crc32 /usr/local /usr/local
COPY --from=protobuf /usr/local /usr/local
COPY --from=grpc /usr/local /usr/local
RUN ldconfig
# Google-cloud-cpp Install
ARG GCCPP_VERSION="v1.35.0"
WORKDIR /build/src
RUN curl -sSL https://github.com/googleapis/google-cloud-cpp/archive/${GCCPP_VERSION}.tar.gz | tar -xzf - --strip-components=1
WORKDIR /build/build
RUN cmake -GNinja -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=0 -DBUILD_TESTING=OFF -DGOOGLE_CLOUD_CPP_ENABLE_EXAMPLES=OFF -DGOOGLE_CLOUD_CPP_ENABLE=pubsub ../src
RUN ninja install

FROM base as devcontainer

COPY --from=aws_sdk /usr/local /usr/local
COPY --from=google_sdk /usr/local /usr/local
COPY --from=wolfssl /usr/local /usr/local
COPY --from=openssl /usr/local /usr/local
COPY --from=curl /usr/local /usr/local
COPY --from=hiredis /usr/local /usr/local
RUN ldconfig

WORKDIR /workspace
