FROM alpine:3.22.2 AS build

# Install Zig
ARG ZIG_VER=0.16.0
RUN apk add --no-cache curl xz
RUN curl https://ziglang.org/download/${ZIG_VER}/zig-$(uname -m)-linux-${ZIG_VER}.tar.xz -o zig.tar.xz && \
tar xf zig.tar.xz && \
mv zig-$(uname -m)-linux-${ZIG_VER}/ /opt/zig
ENV PATH="/opt/zig:$PATH"

# Build the app
WORKDIR /build

# Zig Deps
COPY build.zig build.zig.zon ./
RUN zig build --fetch

# Node Deps
RUN apk add --no-cache nodejs npm
COPY site/package.json site/package-lock.json ./site/
RUN cd site && npm ci

# Ziex Exe
COPY src ./src
COPY vendor ./vendor
COPY pkg ./pkg

# Ziex Site
COPY site/build.zig site/build.zig.zon ./site/
RUN cd site && zig build --fetch
RUN cd site && zig build zx -- version

# Ziex Site - Playground Assets
RUN cd site && zig build pg

# Ziex Site - App
COPY site/app ./site/app
RUN cd site && zig build
RUN cd site && zig build zx -- bundle

# Run Ziex Site
FROM scratch
WORKDIR /app
COPY --from=build /build/site/bundle /app
ENTRYPOINT ["/app/ziex_dev", "--rootdir", "/app/static"]