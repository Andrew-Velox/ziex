FROM rust:1.96.0-alpine AS builder
ENV CARGO_BUILD_LOCKED=1

RUN apk update && apk add --no-cache bash curl npm libc-dev binaryen
RUN npm install -g sass
RUN curl --proto '=https' --tlsv1.3 -LsSf https://github.com/leptos-rs/cargo-leptos/releases/latest/download/cargo-leptos-installer.sh | sh
RUN rustup target add wasm32-unknown-unknown

WORKDIR /work
COPY src src
COPY Cargo.toml Cargo.toml
COPY Cargo.lock Cargo.lock

RUN cargo leptos build --release -vv

FROM alpine:3.22.2 AS runner
WORKDIR /app

RUN apk add --no-cache curl

COPY --from=builder /work/target/release/leptos-ssr /app/
COPY --from=builder /work/target/site /app/site
COPY --from=builder /work/Cargo.toml /app/

ENV RUST_LOG="info"
ENV LEPTOS_SITE_ADDR="0.0.0.0:3000"
ENV LEPTOS_SITE_ROOT=./site
EXPOSE 3000

CMD ["/app/leptos-ssr"]
