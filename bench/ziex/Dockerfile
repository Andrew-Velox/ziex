FROM alpine:3.22.2 AS build

# Setup Zig
RUN apk add --no-cache curl xz
ARG ZIG_VER=0.17.0-dev.864+3deb86baf
RUN curl https://ziglang.org/builds/zig-$(uname -m)-linux-${ZIG_VER}.tar.xz -o zig.tar.xz && \
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
RUN cd bench/ziex && zig build --release=fast -Dcpu=baseline
# RUN cd bench/ziex && zig build zx -- bundle

# Run app
FROM alpine:3.22.2
WORKDIR /app

RUN apk add --no-cache curl
COPY --from=build /build/bench/ziex/zig-out/bin /app
COPY --from=build /build/bench/ziex/zig-out/static /app

ENTRYPOINT ["/app/ziex_app"]