defmodule AgentBoard.Superagents.RuntimePackage do
  @moduledoc "The ordered extension files shared by first install and synchronization."

  @root Path.expand("../../../priv/agent", __DIR__)
  @manifest Path.join(@root, "extension-files.json")
  @external_resource @manifest
  @files @manifest |> File.read!() |> Jason.decode!()
  @patches Map.fetch!(@files, "patches")
  @helpers Map.fetch!(@files, "helpers")
  @inputs Enum.map(["harness/package-lock.json"] ++ @patches ++ @helpers, &Path.join(@root, &1))
  for path <- @inputs do
    @external_resource path
  end

  @digest :sha256 |> :crypto.hash(Enum.map(@inputs, &File.read!/1)) |> Base.encode16(case: :lower)

  def digest, do: @digest
  def patches, do: @patches
  def helpers, do: @helpers
end
