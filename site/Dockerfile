FROM alpine:3.22.2 AS build

# Install Zig
ARG ZIG_VER=0.16.0
RUN apk add --no-cache curl xz
RUN curl https://ziglang.org/download/${ZIG_VER}/zig-$(uname -m)-linux-${ZIG_VER}.tar.xz -o zig.tar.xz && \
tar xf zig.tar.xz && \
mv zig-$(uname -m)-linux-${ZIG_VER}/ /opt/zig
ENV PATH="/opt/zig:$PATH"

# Build App
WORKDIR /build

# Node Deps
RUN apk add --no-cache nodejs npm
COPY site/package.json site/package-lock.json ./site/
RUN cd site && npm ci

# Ziex CLI
COPY build.zig build.zig.zon ./
COPY src ./src
COPY vendor ./vendor
COPY pkg ./pkg
COPY templates ./templates

COPY site/build.zig site/build.zig.zon ./site/
RUN cd site && zig build --fetch
RUN cd site && zig build zx -- version

# App
RUN cd site && zig build pg

COPY site/app site/component ./site/
COPY pkg/ui ./pkg/ui
RUN cd site && zig build -Doptimize=ReleaseSmall
RUN cd site && zig build zx -- bundle

# Run App
FROM alpine:3.22.2
WORKDIR /app
COPY --from=build /build/site/bundle /app
ENTRYPOINT ["/app/ziex_dev"]