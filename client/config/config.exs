import Config

config :coord_interface, CoordInterface.Application, mode: :embedded

import_config "#{config_env()}.exs"
