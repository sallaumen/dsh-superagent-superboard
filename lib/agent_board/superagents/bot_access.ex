defmodule AgentBoard.Superagents.BotAccess do
  @moduledoc """
  The agent's GitHub source refuses a repository its account cannot push to,
  so a new project gets that access before anything is created: the owner's
  token invites the bot and the bot's own CLI accepts. The caller's action has
  already confirmed this with the owner. Answers say what to do in words; the
  CLI's output is never repeated, as it can carry credentials.
  """

  alias AgentBoard.GitHub

  @writers ~w(admin maintain write)

  @doc "Make sure `bot` can push to the repository."
  @spec ensure(map(), String.t(), String.t(), Req.Request.t(), function()) ::
          :ok | {:error, String.t()}
  def ensure(repository, bot, cli, client \\ GitHub.client(), runner \\ &run/3) do
    %{owner: owner, name: name} = repository

    case GitHub.collaborator_permission(client, owner, name, bot) do
      {:ok, role} when role in @writers -> :ok
      {:ok, _role} -> invite(repository, bot, cli, client, runner)
      :not_found -> {:error, not_found(repository, bot)}
    end
  rescue
    _exception -> {:error, cannot_invite(repository, bot)}
  end

  defp invite(%{owner: owner, name: name} = repository, bot, cli, client, runner) do
    case GitHub.invite_collaborator(client, owner, name, bot) do
      :already -> :ok
      {:invited, id} when is_integer(id) -> accept(repository, bot, cli, id, runner)
      _other -> {:error, cannot_invite(repository, bot)}
    end
  end

  defp accept(repository, bot, cli, id, runner) do
    args = ["api", "--method", "PATCH", "user/repository_invitations/#{id}"]

    # The board's own token is in its environment, and `gh` would prefer it
    # to the bot's login: the invitation is the bot's to accept.
    env = [{"GITHUB_TOKEN", nil}, {"GH_TOKEN", nil}]

    case runner.(cli, args, stderr_to_stdout: true, env: env) do
      {_output, 0} ->
        :ok

      {_output, _code} ->
        {:error,
         "@#{bot} foi convidado para #{slug(repository)}, mas não conseguiu aceitar o convite. " <>
           "Aceite com a conta do bot e tente de novo."}
    end
  end

  # No shell: the CLI path and its arguments stay separate words.
  defp run(cli, args, opts), do: System.cmd("/usr/bin/env", [cli | args], opts)

  defp not_found(repository, bot) do
    "Não encontrei @#{bot} em #{slug(repository)}: a conta não existe ou o token do board não " <>
      "enxerga esse repositório."
  end

  defp cannot_invite(repository, bot) do
    "Não consegui dar acesso de escrita a @#{bot} em #{slug(repository)}. Adicione o bot em " <>
      "https://github.com/#{slug(repository)}/settings/access e tente de novo."
  end

  defp slug(%{owner: owner, name: name}), do: "#{owner}/#{name}"
end
