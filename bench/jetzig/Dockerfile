FROM alpine:3.22.2 AS build

# Setup Zig
ARG ZIG_VER=0.15.2
RUN wget https://ziglang.org/download/${ZIG_VER}/zig-$(uname -m)-linux-${ZIG_VER}.tar.xz && \
    tar -xf zig-*.tar.xz && \
    rm zig-*.tar.xz && \
    mv zig-*/ /opt/zig && \
    ln -s /opt/zig/zig /usr/local/bin/zig

# Build the app
WORKDIR /build

COPY build.zig build.zig.zon ./
RUN zig build --fetch

COPY src/ ./src/
RUN zig build -Doptimize=ReleaseFast -Dcpu=baseline

# Run the app
FROM alpine:3.22.2

COPY --from=build /build/zig-out/bin/jetzig-demo /app/jetzig-demo
ENTRYPOINT ["/app/jetzig-demo", "-b", "0.0.0.0", "-p", "3000"]
