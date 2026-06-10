FROM alpine:3.22.2 AS build

# Setup Zig
ARG ZIG_VER=0.16.0
RUN apk add --no-cache curl xz
RUN curl https://ziglang.org/download/${ZIG_VER}/zig-$(uname -m)-linux-${ZIG_VER}.tar.xz -o zig.tar.xz && \
tar xf zig.tar.xz && \
mv zig-$(uname -m)-linux-${ZIG_VER}/ /opt/zig
ENV PATH="/opt/zig:$PATH"

# Build app
WORKDIR /build

# Ziex CLI
COPY build.zig build.zig.zon ./
COPY src/ ./src/
COPY vendor/ ./vendor/
COPY pkg/ pkg/
COPY templates/Template.zig templates/Template.zig
COPY templates/_base templates/_base
COPY templates/_docker templates/_docker

COPY ./bench/ziex/build.zig bench/ziex/build.zig.zon ./bench/ziex/
RUN cd bench/ziex && zig build --fetch
RUN cd bench/ziex &&  zig build zx -- version

# App
COPY ./bench/ziex/app ./bench/ziex/app
RUN cd bench/ziex && zig build -Doptimize=ReleaseFast
RUN cd bench/ziex &&  zig build zx -- bundle

# Run app
FROM alpine:3.22.2
WORKDIR /app

RUN apk add --no-cache curl
COPY --from=build /build/bench/ziex/bundle /app

ENTRYPOINT ["/app/zx_bench_client"]