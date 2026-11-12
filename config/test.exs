import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :agent_board, AgentBoard.Repo,
  username: "board",
  password: "board",
  hostname: "127.0.0.1",
  port: 5434,
  database: "agent_board_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :agent_board, AgentBoardWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  # Phoenix.ConnTest's host, so the endpoint's host allowlist lets tests in.
  url: [host: "www.example.com"],
  secret_key_base: "tdMGzqIS+LJ/7BuPCYb2MfBggrd/2vCezFfQI0RMYJ9nrlkB+LmU2AQQ+HA4diJf",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# The stager/cron plugins must not run against the sandbox: without this the
# Oban stager logs DBConnection errors on every test run.
config :agent_board, Oban, testing: :manual

# The supervised poller must not tick while the suite runs: a poll in the
# shared sandbox window would broadcast into the PubSub topics the tests
# listen to (and a sandbox owner exit could crash it mid-query). One hour
# keeps it alive but silent; ticket_poller_test overrides the knob for the schedule
# test.
config :agent_board, ticket_poll_interval: 3_600_000
config :agent_board, message_poll_interval: 3_600_000

# The automatic retry ticks on the same schedule rule: the suite calls
# AutoRetry.tick/1 itself.
config :agent_board, auto_retry_interval: 3_600_000
config :agent_board, auto_release_interval: 3_600_000

# The summary of the day too: the suite calls DailySummary.tick/1 with its
# own clock.
config :agent_board, daily_summary_interval: 3_600_000

# The runner ticker reads status files; the suite calls Runners.tick/0 itself.
config :agent_board, runner_tick_interval: 3_600_000

# The superagent ticker reads the manager; :manual means it never schedules
# a tick, so the suite drives it (and a sandboxed row cannot be touched by a
# process outside the test).
config :agent_board, superagent_tick_interval: :manual

# A status read the ticker kills (6 s in production) is exercised with a fake
# that answers late; the suite must not wait those seconds.
config :agent_board, superagent_status_timeout_ms: 300

# A stubbed 5xx must not cost the suite the real wait between GitHub retries.
config :agent_board, github_retry_base_ms: 1

# The voices cache would leak between tests through the persistent term;
# the client goes to the stub every time.
config :agent_board, voice_voices_ttl: 0
# Spoken audio is not cached in tests: each stub decides its own answer.
config :agent_board, voice_speech_cache_entries: 0
# Each test edits its own worktree and reads it back at once: no shared
# observation may answer for it.
config :agent_board, worktree_ttl_ms: 0

# The throughput block asks the orchestrator for its load; the suite never
# touches the local runner. A test that needs a value sets
# `:orchestrator_client` to a Req.Test plug.
config :agent_board, orchestrator_api: false

# Retries happen in tests (the stubs answer 429/5xx on purpose) but never wait.
config :agent_board, voice_retry_base_ms: 0

# The header badge's fetch is network work; the component test drives the
# rendered state directly, and LiveView tests keep their original timing.
config :agent_board, version_check_on_mount: false

# A broadcast reloads the board at once in tests: the suite sends
# :board_updated and reads the page right after. board_load_test covers the
# coalesced burst with its own delay.
config :agent_board, board_reload_ms: 0
# The ElevenLabs account is read only when a test asks for it.
config :agent_board, elevenlabs_account_refresh: false

# Settings opens on AI and setup when a required part is missing; the suite
# has no GitHub token nor AI key (CI), so the configuration reading counts them as set.
config :agent_board, :setup_readers,
  config: [
    github: fn -> true end,
    board_ai: fn -> %{provider: :deepseek, model: "deepseek-flash", fallbacks: []} end
  ]

# The agents' installed tools are read from a home a test builds, never the
# developer's own.
config :agent_board, agent_tools_home: "/nonexistent-agent-tools-home"
# The agents' instructions are compared only when a test asks.
config :agent_board, agent_policy_check_on_boot: false
# The daily folder retention removes directories: a test asks for it by name.
config :agent_board, agent_folder_sweep: false
