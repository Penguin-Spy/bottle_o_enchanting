#  connection.ex © Penguin_Spy 2024
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

defmodule MC.Connection do
  require Logger
  import Bitwise

  def init(socket: socket) do
    Logger.info("staring connection genserver for socket #{inspect(socket)}")
    state = %{stage: :handshake, socket: socket, buf: <<>>}
    {:ok, state}
  end

  @doc """
    Tries to read a VarInt from the buffer, and raises an error if it can't.

    Returns a tuple of `{rest, value}` where `rest` is the rest of the buffer and `value` is the integer read.
  """
  def read_varint!(buf) do
    case read_varint(buf) do
      {:ok, buf, value} -> {buf, value}
      _ -> raise "unexpected end of buffer when reading VarInt"
    end
  end

  @doc """
    Tries to read a VarInt from the buffer.

    Returns a tuple of `{:ok, rest, value}` where `rest` is the rest of the buffer and `value` is the integer read.
    If the end of the buffer is reached, returns `{:end}`
  """
  def read_varint(buf) do
    read_varint(buf, 0, 0)
  end

  defp read_varint(buf, value, pos) when byte_size(buf) > 0 do
    if pos > 4, do: raise("VarInt too long!")
    # read the first byte
    <<byte, buf::binary>> = buf
    # add to computed varint value (only include the lower 7 bits of the byte)
    value = ((byte &&& 0x7F) <<< (pos * 7)) + value
    # try to read the next byte if there is one, or return the value if done
    if byte >= 0x80 do
      read_varint(buf, value, pos + 1)
    else
      # return remaining buffer & value
      {:ok, buf, value}
    end
  end

  defp read_varint(_buf, _value, _position) do
    {:end}
  end

  @doc """
    Returns the binary representation of `value` as a VarInt.
  """
  def calc_varint(value) do
    calc_varint(<<>>, value)
  end

  defp calc_varint(buf, value) do
    byte = value &&& 0x7F

    if value > 0x7F do
      calc_varint(buf <> <<byte ||| 0x80>>, value >>> 7)
    else
      buf <> <<byte>>
    end
  end

  @doc """
    Tries to read a String from the buffer, and raises an error if it can't.

    Returns a tuple of `{rest, string}` where `rest` is the rest of the buffer and `string` is the string read.
  """
  def read_string!(buf) do
    case read_string(buf) do
      {:ok, buf, string} -> {buf, string}
      _ -> raise "unexpected end of buffer when reading String"
    end
  end

  @doc """
    Tries to read a string from the buffer.

    Returns a tuple of `{:ok, rest, string}` where `rest` is the rest of the buffer and `string` is the string read.
    If the end of the buffer is reached, returns `{:end}`
  """
  def read_string(buf) do
    case read_varint(buf) do
      {:ok, rest, length} when byte_size(rest) >= length ->
        <<string::binary-size(length), buf::binary>> = rest
        {:ok, buf, string}

      {:ok, _, _} ->
        {:end}

      any ->
        any
    end
  end

  @doc """
    Returns the binary representation of `string` as a network String (prefixed with length VarInt).
  """
  def calc_string(string) do
    # get the number of raw bytes in the string (not the number of Unicode characters/graphemes)
    b = calc_varint(byte_size(string))
    b <> string
  end

  @doc """
    Tries to read a Short from the buffer, and raises an error if it can't.

    Returns a tuple of `{rest, value}` where `rest` is the rest of the buffer and `value` is the short read.
  """
  def read_short!(buf) do
    case read_short(buf) do
      {:ok, buf, value} -> {buf, value}
      _ -> raise "unexpected end of buffer when reading Short"
    end
  end

  @doc """
    Tries to read a Short from the buffer.

    Returns a tuple of `{rest, value}` where `rest` is the rest of the buffer and `value` is the short read.
  """
  def read_short(buf) when byte_size(buf) > 1 do
    <<value::size(16), buf::binary>> = buf
    {:ok, buf, value}
  end

  def read_short(_buf) do
    {:end}
  end

  def encode_chunk_data_array(entries, bits_per_entry) do
    # accumulator is {array, buffer, bits used}
    {array, buffer, bits_used} =
      Enum.reduce(entries, {<<>>, <<>>, 0}, fn entry, acc ->
        {array, buffer, bits_used} = acc

        if(bits_used + bits_per_entry < 64) do
          # have more space still
          buffer = <<entry::size(bits_per_entry), buffer::bits>>
          {array, buffer, bits_used + bits_per_entry}
        else
          # need to start a new Long
          array = array <> <<0::size(64 - bits_used), buffer::bits>>
          buffer = <<entry::size(bits_per_entry)>>
          {array, buffer, bits_per_entry}
        end
      end)

    # finish last Long (if one was started)
    if bits_used != 0 do
      array <>
        <<0::size(64 - bits_used), buffer::bits>>
    else
      array
    end
  end

  # TODO: input block data
  def encode_chunk(chunk_x, chunk_z) do
    # empty heightmaps
    heightmaps = MC.NBT.encode([])

    # generate chunk data
    # array of chunk sections (16 of them):
    #  1 chunk section (subchunk): block count, block states, biomes
    #  palleted container: bits per entry(1)=0, value(VarInt), data array length(VarInt)=0
    chunk_data =
      Enum.reduce(1..16, <<>>, fn item, buf ->
        block_id =
          if chunk_x != 0 or chunk_z != 0 do
            item
          else
            0
          end

        buf <>
          <<4096::integer-16>> <>
          <<0, calc_varint(block_id)::binary, calc_varint(0)::binary>> <>
          <<0, calc_varint(0)::binary, calc_varint(0)::binary>>
      end)

    # chunk X, Z
    # heightmaps
    # chunk data size, chunk data
    # number of block entities, block entity data (empty)
    # sky light mask length, sky light mask bits (empty)
    # block light mask length, block light mask bits (empty)
    # sky light empty length, bits
    # block light empty length, bits
    # sky light data array count
    # block light data array count
    <<chunk_x::32-signed, chunk_z::32-signed>> <>
      heightmaps <>
      <<calc_varint(byte_size(chunk_data))::binary, chunk_data::binary>> <>
      calc_varint(0) <>
      calc_varint(0) <>
      calc_varint(0) <>
      calc_varint(0) <>
      calc_varint(0) <>
      calc_varint(0) <>
      calc_varint(0)
  end

  @doc """
    Sends a packet to the client with the specified packet id and data.
  """
  def send_packet(state, packet_id, data) do
    out_packet = calc_varint(packet_id) <> data
    # prefix with packet length
    out_packet = calc_varint(byte_size(out_packet)) <> out_packet
    # Logger.info("sending packet: #{Base.encode16(out_packet)} in stage #{inspect(state.stage)}")
    :gen_tcp.send(state.socket, out_packet)
  end

  def read_packet(packet, state) do
    stage = state.stage
    # Logger.info("reading packet: #{Base.encode16(packet)} in stage #{inspect(stage)}")
    {packet, packet_id} = read_varint!(packet)

    stage =
      case packet_id do
        0x00 when stage == :handshake ->
          # Begin connection (corresponds to "Connecting to the server..." on the client connection screen)
          {packet, protocol_id} = read_varint!(packet)
          {packet, server_addr} = read_string!(packet)
          {packet, server_port} = read_short!(packet)
          {_, next_state} = read_varint!(packet)
          Logger.info("Handshake packet with protocol id #{inspect(protocol_id)}, address #{server_addr}:#{server_port}, next state: #{next_state}")

          case next_state do
            1 -> :status
            2 -> :login
          end

        0x00 when stage == :status ->
          Logger.info("Status request packet")
          # packet id 0, string of the server status response
          send_packet(state, 0x00, calc_string("{\"version\":{\"name\":\"1.20.4\",\"protocol\":765},\"players\":{\"max\":0,\"online\":2,\"sample\":[{\"name\":\"Penguin_Spy\",\"id\":\"dfbd911d-9775-495e-aac3-efe339db7efd\"}]},\"description\":{\"text\":\"woah haiii :3\"},\"enforcesSecureChat\":false,\"previewsChat\":false,\"preventsChatReports\":true}"))
          :status

        0x01 when stage == :status ->
          Logger.info("Ping request packet: #{inspect(packet)}")
          # the rest of the data ("packet") is all of the data we need to send back
          send_packet(state, 0x01, packet)
          :shutdown

        0x00 when stage == :login ->
          {packet, username} = read_string!(packet)
          <<uuid::binary-size(16), _::binary>> = packet
          Logger.info("Login packet with username #{inspect(username)} and uuid #{inspect(uuid)}")
          # Send login success (corresponds to "Joining world..." on the client connection screen)
          send_packet(state, 0x02, uuid <> calc_string(username) <> calc_varint(0))
          :login_wait_ack

        0x03 when stage == :login_wait_ack ->
          Logger.info("Login ack received, sending registry and ending configuration")
          # send registry data
          send_packet(state, 0x05, MC.Server.get_registry())
          # tell client we're finished with configuration, u can ack when you're done sending stuff
          send_packet(state, 0x02, <<>>)
          :configuration

        0x00 when stage == :configuration ->
          Logger.info("Client configuration info received")
          stage

        0x01 when stage == :configuration ->
          {packet, channel} = read_string!(packet)
          Logger.info("serverbound plugin message (configuration) to #{inspect(channel)} with data #{inspect(packet)}")
          stage

        0x02 when stage == :configuration ->
          Logger.info("Client configuration finish ack received")
          # Send login (Corresponds to "Loading terrain..." on the client connection screen)
          # Entity ID (4), Hardcore? (1),
          # Dimension Count (VarInt), [would be dimensions],
          # Max players (VarInt, unused),
          # View Distance (VarInt),
          # Simulation Distance (VarInt),
          # Reduced debug (1), enable respawn screen (1), limited crafting? (1),
          # starting dimension type (?) (String),
          # starting dimension name (String),
          # hashed world seed (8), game mode (1), prev game mode (1), debug? (1), flat? (1), has death location? (1)
          # portal cooldown (VarInt, unknown use)
          send_packet(
            state,
            0x29,
            <<0, 0, 0, 0, 1>> <>
              calc_varint(0) <>
              calc_varint(0) <>
              calc_varint(12) <>
              calc_varint(5) <>
              <<0, 1, 0>> <>
              calc_string("minecraft:overworld") <>
              calc_string("minecraft:overworld") <>
              <<0, 0, 0, 0, 0, 0, 0, 0, 1, -1, 0, 0, 0>> <> calc_varint(0)
          )

          # Game event 13 - start waiting for chunks
          send_packet(state, 0x20, <<13, 0::float-32>>)

          # send chunks
          for x <- -2..2 do
            for z <- -2..2 do
              send_packet(state, 0x25, encode_chunk(x, z))
            end
          end

          # synchronize player position
          send_packet(state, 0x3E, <<0::float-64, 280::float-64, 0::float-64, 0::float-32, 0::float-32, 0x00, calc_varint(0)::binary>>)

          # begin keepalive
          :timer.send_after(20_000, {:keepalive})

          :play

        0x10 when stage == :play ->
          {packet, channel} = read_string!(packet)
          Logger.info("serverbound plugin message (play) to #{inspect(channel)} with data #{inspect(packet)}")
          stage

        0x15 when stage == :play ->
          # TODO: figure out how to keep track of if the client responded to the keepalive
          # state = %{state | keepalive: true}
          Logger.debug("received keepalive")
          :timer.send_after(20_000, {:keepalive})
          stage

        0x17 when stage == :play ->
          # Logger.info("Set Player Position")
          stage

        0x18 when stage == :play ->
          # Logger.info("Set Player Position and Rotation")
          stage

        0x19 when stage == :play ->
          # Logger.info("Set Player Rotation")
          stage

        0x1A when stage == :play ->
          Logger.info("Set Player On Ground: #{inspect(packet)}")
          stage

        0x00 when stage == :play ->
          {_, tp_id} = read_varint!(packet)
          Logger.info("confirm teleport: #{inspect(tp_id)}")
          stage

        0x20 when stage == :play ->
          <<flags, _::binary>> = packet
          Logger.info("player abilities: 0b#{Integer.to_string(flags, 2)}")
          stage

        0x22 when stage == :play ->
          Logger.info("Player Command: #{packet}")
          stage

        _ ->
          Logger.error("Unexpected packet id 0x#{Integer.to_string(packet_id, 16)} in stage #{inspect(stage)}")
          :gen_tcp.shutdown(state.socket, :read_write)
          stage
      end

    %{state | stage: stage}
  end

  def check_buffer(state) do
    buf = state.buf
    # check if there's a VarInt for the packet length
    state =
      case read_varint(buf) do
        # legacy server list ping (first 3 bytes are 0xFE 0x01 0xFA, gets parsed as a VarInt of 254, rest 0xFA)
        {:ok, <<0xFA, rest::binary>>, 254} when state.stage == :handshake ->
          <<_::binary-size(26), client_version, _::binary>> = rest
          Logger.notice("legacy server list ping from client version #{client_version}")
          legacy_response = <<0xFF, 0x00, 32>> <> :unicode.characters_to_binary("§1\x00127\x001.20.4\x00woah haiii :3\x000\x000\x00", :utf8, {:utf16, :big})
          :gen_tcp.send(state.socket, legacy_response)
          :gen_tcp.shutdown(state.socket, :read_write)
          %{state | stage: :shutdown}

        # standard data
        {:ok, buf, value} ->
          # if we have received at least all the bytes of this packet
          if(byte_size(buf) >= value) do
            # split out the packet, read it, and return the rest of the buffer
            <<packet::binary-size(value), buf::binary>> = buf
            state = %{state | buf: buf}
            state = read_packet(packet, state)
            # check the buffer again (if 2 packets came in back-to-back)
            check_buffer(state)
          end

        # not enough bytes to read the packet length VarInt yet
        {:end} ->
          state
      end

    state
  end

  def handle_info({:tcp, _socket, data}, state) do
    # add the new received data to the buffer
    buf = state.buf <> data
    # and save the remaining data in the state buffer
    state = %{state | buf: buf}
    # check if there's enough to read a packet (and do so if possible)
    state = check_buffer(state)

    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.notice("tcp closed for socket #{inspect(state.socket)}")
    {:noreply, state}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.error("tcp error for socket #{inspect(state.socket)}: #{reason}")
    {:noreply, state}
  end

  def handle_info({:keepalive}, state) do
    Logger.debug("sending keepalive")
    send_packet(state, 0x24, <<0::64>>)
    {:noreply, state}
  end
end
