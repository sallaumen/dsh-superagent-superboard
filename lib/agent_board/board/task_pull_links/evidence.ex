defmodule AgentBoard.Board.TaskPullLinks.Evidence do
  @moduledoc "Match a task to pull request evidence from its own repository."
  alias AgentBoard.Board.Repository
  alias AgentBoard.GitHub

  @doc "Newest comment with a local PR URL wins; otherwise try the task body. Comments arrive oldest first."
  @spec named_number(String.t() | nil, [map()], Repository.t() | nil) :: integer() | nil
  def named_number(body, comments, repository) do
    Enum.find_value(Enum.reverse(comments), &pull_number(&1.body, repository)) ||
      pull_number(body, repository)
  end

  # Only a link to the task's own repository counts: the number alone would
  # match this repository's PR of the same number.
  defp pull_number(nil, _repository), do: nil
  defp pull_number(_text, nil), do: nil

  defp pull_number(text, %Repository{owner: owner, name: name}) do
    ~r{https://github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)}
    |> Regex.scan(text)
    |> Enum.find_value(fn [_, link_owner, link_name, number] ->
      if String.downcase("#{link_owner}/#{link_name}") == String.downcase("#{owner}/#{name}"),
        do: GitHub.number(number)
    end)
  end
end
