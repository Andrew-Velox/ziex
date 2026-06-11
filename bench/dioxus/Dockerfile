FROM rust:1.93 AS chef
RUN cargo install cargo-chef
WORKDIR /app

FROM chef AS planner
COPY src src
COPY Cargo.toml Cargo.toml
COPY Cargo.lock Cargo.lock

RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
# Install `dx`
RUN curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash
RUN cargo binstall dioxus-cli@0.7.9 --root /.cargo -y --force
ENV PATH="/.cargo/bin:$PATH"

COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json --features web,server
COPY src src
COPY Cargo.toml Cargo.toml
COPY Cargo.lock Cargo.lock
COPY Dioxus.toml Dioxus.toml
COPY index.html index.html

RUN dx bundle --fullstack --release --out-dir /app/dist

FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/dist/server /app/server
COPY --from=builder /app/dist/public /app/public

# set our port and make sure to listen for all connections
ENV PORT=3000
ENV IP=0.0.0.0

EXPOSE 3000

ENTRYPOINT [ "/app/server" ]