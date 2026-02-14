FROM rust:1.85-bookworm AS rust_builder
WORKDIR /work
COPY clients/rendezvous-client/Cargo.toml clients/rendezvous-client/Cargo.lock ./clients/rendezvous-client/
COPY clients/rendezvous-client/src ./clients/rendezvous-client/src
WORKDIR /work/clients/rendezvous-client
RUN cargo build --release

FROM elixir:1.19.4-otp-28 AS elixir_builder
WORKDIR /work/coordinator
COPY coordinator/mix.exs coordinator/mix.lock ./
COPY coordinator/config ./config
RUN mix local.hex --force && mix local.rebar --force && mix deps.get
COPY coordinator/lib ./lib
COPY coordinator/priv ./priv
RUN mix compile

FROM elixir:1.19.4-otp-28
WORKDIR /work

RUN apt-get update \
    && apt-get install -y --no-install-recommends iproute2 iptables curl ca-certificates procps \
    && rm -rf /var/lib/apt/lists/*

COPY --from=rust_builder /work/clients/rendezvous-client/target/release/rendezvous-client /usr/local/bin/rendezvous-client

COPY --from=elixir_builder /work/coordinator /work/coordinator
COPY natlab/run.sh /usr/local/bin/natlab-run

ENV MIX_ENV=dev
EXPOSE 4000
EXPOSE 3478/udp

ENTRYPOINT ["/usr/local/bin/natlab-run"]
