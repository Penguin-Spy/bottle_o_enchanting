#  server.ex © Penguin_Spy 2024
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

defmodule MC.Server do
  require Logger

  def listen(port) do
    {:ok, socket} = :gen_tcp.listen(port, [:binary, active: true, reuseaddr: true])
    Logger.info("listening on port #{port}")
    loop_accept(socket)
  end

  defp loop_accept(socket) do
    case :gen_tcp.accept(socket) do
      {:ok, client_socket} ->
        {:ok, pid} = GenServer.start(MC.Connection, socket: client_socket)
        :gen_tcp.controlling_process(client_socket, pid)

      err ->
        Logger.info("err accept: #{inspect(err)}")
    end

    loop_accept(socket)
  end

  def get_registry() do
    damage_types =
      for name <- ["in_fire", "lightning_bolt", "on_fire", "lava", "hot_floor", "in_wall", "cramming", "drown", "starve", "cactus", "fall", "fly_into_wall", "out_of_world", "generic", "magic", "wither", "dragon_breath", "dry_out", "sweet_berry_bush", "freeze", "stalagmite", "outside_border", "generic_kill"] do
        [
          {:string, "name", "minecraft:" <> name},
          {:int, "id", 0},
          {:compound, "element",
           [
             {:string, "message_id", "death.attack." <> name},
             {:string, "scaling", "never"},
             {:float, "exhaustion", 0.0},
             {:string, "effects", "hurt"}
           ]}
        ]
      end

    MC.NBT.encode([
      {:compound, "minecraft:worldgen/biome",
       [
         {:string, "type", "minecraft:worldgen/biome"},
         {:list, "value",
          {:compound,
           [
             [
               {:string, "name", "minecraft:plains"},
               {:int, "id", 0},
               {:compound, "element",
                [
                  {:byte, "has_precipitation", 1},
                  {:float, "temperature", 0.5},
                  {:float, "downfall", 0.5},
                  {:compound, "effects",
                   [
                     {:int, "fog_color", 8_364_543},
                     {:int, "water_color", 8_364_543},
                     {:int, "water_fog_color", 8_364_543},
                     {:int, "sky_color", 8_364_543}
                     # a bunch of optional values are omitted
                   ]}
                ]}
             ]
           ]}}
       ]},
      {:compound, "minecraft:dimension_type",
       [
         {:string, "type", "minecraft:dimension_type"},
         {:list, "value",
          {:compound,
           [
             [
               {:string, "name", "minecraft:overworld"},
               {:int, "id", 0},
               {:compound, "element",
                [
                  {:byte, "has_skylight", 1},
                  {:byte, "has_ceiling", 0},
                  {:byte, "ultrawarm", 0},
                  {:byte, "natural", 1},
                  {:double, "coordinate_scale", 1},
                  {:byte, "bed_works", 1},
                  {:byte, "respawn_anchor_works", 0},
                  {:int, "min_y", 0},
                  {:int, "height", 256},
                  {:int, "logical_height", 256},
                  {:string, "infiniburn", "#minecraft:infiniburn_overworld"},
                  {:string, "effects", "minecraft:overworld"},
                  {:float, "ambient_light", 0.0},
                  {:byte, "piglin_safe", 0},
                  {:byte, "has_raids", 1},
                  {:int, "monster_spawn_light_level", 0},
                  {:int, "monster_spawn_block_light_limit", 0}
                ]}
             ]
           ]}}
       ]},
      {:compound, "minecraft:damage_type",
       [
         {:string, "type", "minecraft:damage_type"},
         {:list, "value", {:compound, damage_types}}
       ]}
    ])
  end
end
