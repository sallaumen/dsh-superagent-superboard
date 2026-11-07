defmodule AgentBoard.Usage.Fields do
  @moduledoc """
  Decodes one JSON line of a local transcript keeping only what a usage
  reader may see: numbers, booleans, objects that still hold something
  after filtering, and the strings under the keys the reader names.

  Every other string and every array is dropped while the line is parsed,
  so conversation text (a message's `content`, a title, a prompt, a tool's
  input or output) never reaches the caller's term. A reader that needs a
  new string field has to name it here, in the open, and a test pins the
  list (`AgentBoard.Usage.ClaudeCodeTest`, "privacy").
  """

  @doc """
  The filtered object, or `:error` when the line is not one JSON object.
  `strings` are the keys whose string values are kept, at any depth.
  """
  @spec decode(binary(), MapSet.t(String.t())) :: {:ok, map()} | :error
  def decode(line, %MapSet{} = strings) when is_binary(line) do
    decoders = %{
      array_push: fn _value, acc -> acc end,
      array_finish: fn _acc, old -> {[], old} end,
      object_push: fn key, value, acc ->
        if keep?(key, value, strings), do: [{key, value} | acc], else: acc
      end,
      null: nil
    }

    case :json.decode(line, :ok, decoders) do
      {object, :ok, rest} when is_map(object) ->
        if String.trim(rest) == "", do: {:ok, object}, else: :error

      _ ->
        :error
    end
  catch
    :error, _reason -> :error
  end

  defp keep?(_key, value, _strings) when is_number(value) or is_boolean(value), do: true
  defp keep?(_key, value, _strings) when is_map(value), do: map_size(value) > 0
  defp keep?(key, value, strings) when is_binary(value), do: MapSet.member?(strings, key)
  defp keep?(_key, _value, _strings), do: false
end
