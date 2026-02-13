FROM elixir:1.19.4-otp-28

WORKDIR /app

ENV MIX_ENV=dev

RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

COPY mix.exs mix.lock ./
COPY config ./config
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get

COPY lib ./lib
COPY priv ./priv

RUN mix compile

EXPOSE 4000
EXPOSE 3478/udp

CMD ["mix", "phx.server"]
