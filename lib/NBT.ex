defmodule MC.NBT do
  require Logger

  @doc """
    Encodes a list of tuples of {:type, "name", value} as a network-ready NBT compound binary.
  """
  def encode(list) do
    # begin with (nameless) root compound tag
    <<0x0A>> <> encode_compound(list)
  end

  defp encode_type(type, value) do
    case type do
      :byte -> {1, encode_byte(value)}
      :short -> {2, encode_short(value)}
      :int -> {3, encode_int(value)}
      :long -> {4, encode_long(value)}
      :float -> {5, encode_float(value)}
      :double -> {6, encode_double(value)}
      :string -> {8, encode_string(value)}
      :compound -> {10, encode_compound(value)}
      :list -> {9, encode_list(value)}
    end
  end

  # explicitly declare the size & attributes of these because the defaults weren't matching the documentation
  defp encode_byte(value), do: <<value::integer-8-signed-big>>
  defp encode_short(value), do: <<value::integer-16-signed-big>>
  defp encode_int(value), do: <<value::integer-32-signed-big>>
  defp encode_long(value), do: <<value::integer-64-signed-big>>
  defp encode_float(value), do: <<value::float-32-big>>
  defp encode_double(value), do: <<value::float-64-big>>
  # this incorrectly encodes it as a normal UTF-8 string, not a Java™ modified UTF-8 string.
  defp encode_string(value), do: <<byte_size(value)::integer-16-unsigned>> <> value

  defp encode_compound(items) do
    Enum.reduce(items, <<>>, fn item, buf ->
      {type, name, value} = item
      {encoded_type, encoded_payload} = encode_type(type, value)
      buf <> <<encoded_type>> <> encode_string(name) <> encoded_payload
    end) <> <<0x00>>
  end

  defp encode_list({type, items}) do
    # this will fail with an empty list. and also it just sucks
    {encoded_type, encoded_first} = encode_type(type, hd(items))
    buf = <<encoded_type>> <> encode_int(length(items)) <> encoded_first

    Enum.reduce(tl(items), buf, fn item, buf ->
      {_, encoded} = encode_type(type, item)
      buf <> encoded
    end)
  end
end
