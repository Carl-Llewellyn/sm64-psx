FROM debian:bookworm AS toolchain

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    bison \
    flex \
    libgmp-dev \
    libmpc-dev \
    libmpfr-dev \
    texinfo \
    wget \
    ca-certificates \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

ARG TARGET=mipsel-none-elf
ARG PREFIX=/opt/${TARGET}
ARG BINUTILS_VERSION=2.45
ARG GCC_VERSION=13.2.0

WORKDIR /tmp/toolchain

RUN wget -q https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz && \
    tar -xf binutils-${BINUTILS_VERSION}.tar.xz && \
    mkdir binutils-build && \
    cd binutils-build && \
    ../binutils-${BINUTILS_VERSION}/configure \
        --target=${TARGET} \
        --prefix=${PREFIX} \
        --with-sysroot \
        --disable-nls \
        --disable-werror \
        --disable-gdb \
        --disable-sim && \
    make -j$(nproc) && \
    make install

RUN wget -q https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz && \
    tar -xf gcc-${GCC_VERSION}.tar.xz && \
    mkdir gcc-build && \
    cd gcc-build && \
    ../gcc-${GCC_VERSION}/configure \
        --target=${TARGET} \
        --prefix=${PREFIX} \
        --disable-nls \
        --disable-libssp \
        --disable-multilib \
        --disable-threads \
        --disable-shared \
        --enable-languages=c \
        --without-headers \
        --with-arch=r3000 \
        --with-abi=eabi \
        --with-endian=little \
        --with-float=soft && \
    make -j$(nproc) all-gcc && \
    make -j$(nproc) all-target-libgcc && \
    make install-gcc && \
    make install-target-libgcc

RUN rm -rf /tmp/toolchain

ENV PATH=${PREFIX}/bin:${PATH}

FROM debian:bookworm AS env

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    python3 \
    git \
    pkg-config \
    bsdextrautils \
    meson \
    ninja-build \
    unzip \
    wget \
    ca-certificates \
    libpng-dev \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libswresample-dev \
    libswscale-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=toolchain /opt/mipsel-none-elf /opt/mipsel-none-elf
ENV PATH=/opt/mipsel-none-elf/bin:${PATH}

WORKDIR /sm64-psx

FROM env AS build

COPY --link . .

RUN make -C tools -j$(nproc) all-except-recomp

ARG VERSION=us
RUN make -j$(nproc) VERSION=${VERSION}

FROM build AS artifacts
ARG VERSION=us
RUN mkdir -p /artifacts && \
    cp /sm64-psx/build/${VERSION}_psx/sm64.iso /artifacts/sm64.${VERSION}.iso && \
    cp /sm64-psx/build/${VERSION}_psx/sm64.cue /artifacts/sm64.${VERSION}.cue

VOLUME ["/out"]
CMD ["bash", "-lc", "mkdir -p /out && cp /artifacts/* /out/"]
