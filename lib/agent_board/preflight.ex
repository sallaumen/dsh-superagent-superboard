defmodule AgentBoard.Preflight do
  @moduledoc """
  Last observed local preflight in one executor worktree. Only the script writes
  evidence; the board never uses these receipts to authorize a merge.
  """

  @stages ~w(backend frontend library)
  @ui_reasons ~w(screen interaction appearance copy unknown)
  @max_receipt 1024

  def source(
        %{"repository" => repo, "execution" => %{"directory" => dir}, "started_at" => since} =
          ticket
      )
      when is_binary(repo),
      do: source(dir, since, ticket["ended_at"])

  def source(%{worktree: dir, started_at: since, finished_at: until}),
    do: source(dir, since, until)

  def source(_), do: nil

  defp source("/" <> _ = dir, %DateTime{} = since, until),
    do:
      {dir, DateTime.to_unix(since, :microsecond), until && DateTime.to_unix(until, :microsecond)}

  defp source(_, _, _), do: nil

  def read({dir, since, until}) do
    key = :crypto.hash(:sha256, Path.expand(dir)) |> Base.encode16(case: :lower)

    root =
      System.get_env("SUPERBOARD_PREFLIGHT_DIR") ||
        Path.expand("~/.local/state/superboard/preflight")

    path = Path.join(root, key <> ".json")

    with {:ok, bytes} <- read_receipt(path),
         {:ok, data} <- Jason.decode(bytes) do
      snapshot(data, since, until)
    else
      _ -> nil
    end
  end

  def read(nil), do: nil

  # Read at most one receipt even if the writer replaces it between stat and open.
  defp read_receipt(path) do
    with {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, file} <- :file.open(path, [:read, :raw, :binary]) do
      try do
        case :file.pread(file, 0, @max_receipt + 1) do
          {:ok, bytes} when byte_size(bytes) <= @max_receipt -> {:ok, bytes}
          _ -> :error
        end
      after
        :file.close(file)
      end
    end
  end

  defp snapshot(
         %{"head" => head, "started" => began, "state" => state, "stage" => stage, "at" => at} =
           data,
         since,
         until
       )
       when is_integer(began) and is_integer(at) and is_binary(head) and
              state in ~w(running passed failed interrupted unavailable) do
    reason = data["ui_reason"]
    stages = if reason in @ui_reasons, do: @stages ++ ["ui_review"], else: @stages

    if in_attempt?(began, since, until) and valid_stage?(state, stage, stages) and
         head =~ ~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/ do
      state = observed(state, at, until)

      %{
        head: head,
        stage: stage,
        state: state,
        rows: rows(stage, state, stages),
        ui_failure: data["ui_failure"],
        ui_reason: reason
      }
    end
  end

  defp snapshot(_, _, _), do: nil

  defp valid_stage?("passed", stage, stages), do: stage == List.last(stages)
  defp valid_stage?("unavailable", stage, stages), do: stage == "ui_review" and stage in stages
  defp valid_stage?(_, stage, stages), do: stage in stages

  defp in_attempt?(began, since, until), do: began >= since and (is_nil(until) or began <= until)

  defp observed("running", at, until) do
    if until != nil or System.os_time(:second) - at > 60, do: "unconfirmed", else: "running"
  end

  defp observed(state, _at, _until), do: state

  defp rows(stage, state, stages) do
    {done, [_ | next]} = Enum.split_while(stages, &(&1 != stage))
    later = if state in ~w(failed interrupted), do: "not_run", else: "pending"
    Enum.map(done, &{&1, "passed"}) ++ [{stage, state}] ++ Enum.map(next, &{&1, later})
  end
end
