import Config

# `.env.local` feeds the environment before any config below. The shell still
# wins: a variable already set to a non-blank value is left alone. The suite
# never applies it, so tests do not depend on a developer's local file.
# AGENT_BOARD_ENV_FILE overrides the path (useful for a worktree).
if config_env() != :test do
  env_file = System.get_env("AGENT_BOARD_ENV_FILE") || Path.expand("../.env.local", __DIR__)

  if File.exists?(env_file) do
    for line <- File.stream!(env_file) do
      case String.split(String.trim(line), "=", parts: 2) do
        [key, value] ->
          key = String.trim(key)

          if key != "" and not String.starts_with?(key, "#") and
               System.get_env(key) in [nil, ""] do
            System.put_env(key, String.trim(value, "\""))
          end

        _ ->
          :ok
      end
    end
  end
end

if System.get_env("PHX_SERVER") do
  config :agent_board, AgentBoardWeb.Endpoint, server: true
end

# LOG_LEVEL=info|warning|error|debug overrides the environment's level. The
# 4099 service sets info: in dev the default debug level logs every query,
# which grew its log to almost 1 GB of SQL with the errors buried in it.
if config_env() != :test do
  case System.get_env("LOG_LEVEL") do
    level when level in ~w(debug info notice warning error) ->
      config :logger, level: String.to_existing_atom(level)

    _ ->
      :ok
  end
end

# The voice defaults come from the environment when present; the key itself
# (ELEVENLABS_API_KEY) is read straight from the environment by
# AgentBoard.ElevenLabs. Only set a key that exists: a nil app key would
# shadow the module default.
for {env, app} <- [
      {"ELEVENLABS_VOICE_ID", :elevenlabs_voice_id},
      {"ELEVENLABS_TTS_MODEL", :elevenlabs_tts_model},
      {"ELEVENLABS_STT_MODEL", :elevenlabs_stt_model}
    ],
    value when is_binary(value) and value != "" <- [System.get_env(env)] do
  config :agent_board, [{app, value}]
end

config :agent_board, AgentBoardWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :agent_board, AgentBoard.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :agent_board, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # The panel's own model key. Absent means the AI layer answers
  # :not_configured instead of reaching the network.
  config :agent_board, :ai_api_key, System.get_env("DEEPSEEK_API_KEY")

  # Which provider answers; nil lets the catalog pick the first with a key.
  config :agent_board, :ai_provider, System.get_env("AI_PROVIDER")

  # The daily ceiling. A Flash refine costs cents; 5M tokens is a working day
  # of intake and questions, not a demo.
  config :agent_board, :ai_daily_tokens, System.get_env("AI_DAILY_TOKENS", "5000000")

  # Rehearsal answers every call with a free fixture -- the panel works end to
  # end without a key, in development only.
  config :agent_board, :ai_rehearsal, System.get_env("AI_REHEARSAL") == "1"

  config :agent_board, AgentBoardWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :agent_board, AgentBoardWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :agent_board, AgentBoardWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
