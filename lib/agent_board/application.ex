defmodule AgentBoard.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AgentBoardWeb.Telemetry,
      AgentBoard.Repo,
      {Oban, Application.fetch_env!(:agent_board, Oban)},
      AgentBoard.AgentWorktree.Cache,
      AgentBoard.Live,
      AgentBoard.AutoRetry,
      AgentBoard.DailySummary,
      AgentBoard.Runners.Ticker,
      AgentBoard.ElevenLabs.SpeechCache,
      {DNSCluster, query: Application.get_env(:agent_board, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AgentBoard.PubSub},
      AgentBoard.Voice.Activity,
      # Start a worker by calling: AgentBoard.Worker.start_link(arg)
      # {AgentBoard.Worker, arg},
      # Start to serve requests, typically the last entry
      AgentBoardWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AgentBoard.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AgentBoardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
