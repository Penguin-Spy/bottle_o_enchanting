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
end
