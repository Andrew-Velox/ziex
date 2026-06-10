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

# Node.js dependencies
# RUN apk add --no-cache nodejs npm
# COPY package.json package-lock.json ./
# RUN npm install

# Ziex CLI
COPY build.zig build.zig.zon ./
RUN zig build --fetch
RUN zig build zx -- version

# App
COPY app/ ./app/
RUN zig build -Doptimize=ReleaseSafe
RUN zig build zx -- bundle

# Run App
FROM alpine:3.22.2
WORKDIR /app
COPY --from=build /build/bundle/ /app/
ENTRYPOINT ["/app/$BIN_NAME"]
