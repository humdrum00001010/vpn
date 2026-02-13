FROM rust:1.93-bookworm AS build

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /app/target/release/rendezvous-client /usr/local/bin/rendezvous-client
ENTRYPOINT ["/usr/local/bin/rendezvous-client"]
