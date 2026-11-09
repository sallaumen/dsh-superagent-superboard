# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :agent_board,
  ecto_repos: [AgentBoard.Repo],
  generators: [timestamp_type: :utc_datetime],
  # A running ticket with no report and no worktree change for this long is
  # a silence the owner should see (AgentBoard.AgentSignal).
  stall_after_ms: 15 * 60 * 1000

# Configure the endpoint
config :agent_board, AgentBoardWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AgentBoardWeb.ErrorHTML, json: AgentBoardWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AgentBoard.PubSub,
  live_view: [signing_salt: "nIxAtcvm"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  agent_board: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  agent_board: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# The sync runs as a durable job: supervised, retried and observable.
config :agent_board, Oban,
  repo: AgentBoard.Repo,
  # usage: the usage ledger reads local transcripts, one run at a time.
  queues: [sync: 1, usage: 1],
  # Every five minutes, not every minute: one run costs ~2 API calls per open
  # or just-ended pull (`Sync.rollup_for/5`), and the account has 5k/h for
  # every repository together (past it the board freezes until the hour resets).
  plugins: [
    Oban.Plugins.Pruner,
    # A restart (launchctl kickstart -k) leaves the running job `executing`
    # for good; Oban starts no Lifeline unless asked. 30 minutes is far above
    # the longest normal run (a full usage read, 3-4 min; a sync, seconds):
    # Lifeline judges by time alone and must never take a live job.
    {Oban.Lifeline, rescue_after: {30, :minutes}},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/5 * * * *", AgentBoard.Sync.Worker},
       {"*/5 * * * *", AgentBoard.Usage.Worker}
     ]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
