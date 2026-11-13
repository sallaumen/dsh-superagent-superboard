defmodule AgentBoard.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias AgentBoard.Superagents.Policy

  @impl true
  def start(_type, _args) do
    children = [
      AgentBoardWeb.Telemetry,
      AgentBoard.Repo,
      # Before anything that can broadcast: a job started by Oban at boot.
      {Phoenix.PubSub, name: AgentBoard.PubSub},
      {Oban, Application.fetch_env!(:agent_board, Oban)},
      AgentBoard.AgentWorktree.Cache,
      AgentBoard.TicketPoller,
      AgentBoard.MessagePoller,
      AgentBoard.AutoRetry,
      AgentBoard.Release,
      AgentBoard.DailySummary,
      AgentBoard.Runners.Ticker,
      {Task.Supervisor, name: AgentBoard.Superagents.TaskSupervisor},
      {Task.Supervisor, name: AgentBoard.System.TaskSupervisor},
      AgentBoard.Superagents.RuntimeSync,
      AgentBoard.Superagents.Ticker,
      AgentBoard.ElevenLabs.SpeechCache,
      AgentBoard.ElevenLabs.Account,
      policy_check(),
      {DNSCluster, query: Application.get_env(:agent_board, :dns_cluster_query) || :ignore},
      AgentBoard.Voice.Activity,
      # Start a worker by calling: AgentBoard.Worker.start_link(arg)
      # {AgentBoard.Worker, arg},
      # Start to serve requests, typically the last entry
      AgentBoardWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AgentBoard.Supervisor]
    result = Supervisor.start_link(children, opts)
    AgentBoard.ObanRescue.rescue_orphans()
    result
  end

  # A board update is when the agents' policy can have changed: each agent is
  # compared once at boot, for the Attention bell. It only reads, and an agent
  # that does not answer is left unknown (`Superagents.Policy`).
  defp policy_check do
    run =
      if Application.get_env(:agent_board, :agent_policy_check_on_boot, true),
        do: &Policy.refresh_all/0,
        else: fn -> :ok end

    Supervisor.child_spec({Task, run}, id: :agent_policy_check, restart: :temporary)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AgentBoardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
