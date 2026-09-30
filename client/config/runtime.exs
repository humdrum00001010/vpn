import Config

if Burrito.Util.running_standalone?() do
  config :coord_interface, CoordInterface.Application, mode: :cli
end
