# The dev seed: the repositories the board tracks out of the box.
#
#   mix run priv/repo/seeds.exs
#
# Idempotent: adding the same repository twice is a no-op.

for {owner, name} <- [{"sallaumen", "arena-rogue"}, {"sallaumen", "o_colmex"}] do
  case AgentBoard.Board.add_repository(owner, name) do
    {:ok, repo} -> IO.puts("tracked #{repo.owner}/#{repo.name}")
    {:error, changeset} -> IO.puts("skipped #{owner}/#{name}: #{inspect(changeset.errors)}")
  end
end
