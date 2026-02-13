import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :coordinator, CoordinatorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "gl2PIkG9W11Ti1vNQ0GQuWmNa3+JRuCV3d9M/so8AIHnPcm9Me2zB+h4LEaEeUOY",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
