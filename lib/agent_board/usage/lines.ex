defmodule AgentBoard.Usage.Lines do
  @moduledoc """
  Folds over the lines of a local transcript without holding the file in
  memory: plain files are streamed by `File.stream!/3`, and zstd files
  (`.zst`, `.zstd`) are decompressed by the `zstd` binary on the PATH and
  split as the output arrives. OTP 27 has no native zstd.
  """

  defmodule Sink do
    @moduledoc false
    defstruct buffer: "", acc: nil, fun: nil

    defimpl Collectable do
      def into(sink), do: {sink, &collect/2}

      # The partial last line is kept as iodata, so a line spread over many
      # chunks is copied once, when it ends.
      defp collect(sink, {:cont, chunk}) do
        case :binary.split(chunk, "\n", [:global]) do
          [partial] ->
            %{sink | buffer: [sink.buffer, partial]}

          [first | more] ->
            {complete, [rest]} = Enum.split(more, -1)
            lines = [IO.iodata_to_binary([sink.buffer, first]) | complete]
            %{sink | buffer: rest, acc: Enum.reduce(lines, sink.acc, sink.fun)}
        end
      end

      defp collect(sink, :done) do
        case IO.iodata_to_binary(sink.buffer) do
          "" -> sink
          last -> %{sink | buffer: "", acc: sink.fun.(last, sink.acc)}
        end
      end

      defp collect(_sink, :halt), do: :ok
    end
  end

  @doc """
  `fun.(line, acc)` for every line, without the newline. `{:error, reason}`
  when the file cannot be opened, `zstd` is missing (`:zstd_missing`) or it
  fails on a corrupt file (`{:zstd, status}`).
  """
  @spec reduce(String.t(), acc, (binary(), acc -> acc)) :: {:ok, acc} | {:error, term()}
        when acc: term()
  def reduce(path, acc, fun) do
    if zstd?(path), do: reduce_zstd(path, acc, fun), else: reduce_plain(path, acc, fun)
  end

  @doc "Whether the file is zstd-compressed, by its extension."
  @spec zstd?(String.t()) :: boolean()
  def zstd?(path), do: Path.extname(path) in [".zst", ".zstd"]

  defp reduce_plain(path, acc, fun) do
    acc =
      path
      |> File.stream!(:line, [])
      |> Enum.reduce(acc, fn line, acc -> fun.(String.trim_trailing(line, "\n"), acc) end)

    {:ok, acc}
  rescue
    error in File.Error -> {:error, error.reason}
  end

  # `zstd` comes from the PATH; the launchd service's PATH includes Homebrew
  # (`ops/com.agentboard.plist`).
  defp reduce_zstd(path, acc, fun) do
    cond do
      is_nil(System.find_executable("zstd")) ->
        {:error, :zstd_missing}

      not File.regular?(path) ->
        {:error, :enoent}

      true ->
        case System.cmd("zstd", ["-dc", "-qq", "--", path], into: %Sink{acc: acc, fun: fun}) do
          {%Sink{acc: acc}, 0} -> {:ok, acc}
          {_sink, status} -> {:error, {:zstd, status}}
        end
    end
  end
end
