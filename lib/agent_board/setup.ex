defmodule AgentBoard.Setup do
  @moduledoc """
  What the board needs to work, in the order one part depends on another, and
  whether each part holds. Settings shows it; the first required part that is
  missing or failing is the owner's next step.

  Two readings, one contract:

    * `checklist/1` reads configuration only (environment, this Mac's files,
      the database): no network, safe on any render. A key that is set is
      `:configured`, never `:ok`: only a check proves it works.
    * `verify/1` proves each part with the provider's free read, and runs only
      on the owner's click: GitHub's `/user`, the answering AI provider's
      `/models`, each superagent's `/state`, `claude auth status`,
      `codex login status`, ElevenLabs' subscription. None spends money or
      writes anything.

  A board with no agent yet also says what a first DeepSeek agent needs on
  this machine: the tools its install runs (`:agent_tools`) and a GitHub
  sign-in of its own (`:agent_bot`). Both are optional, so what is not there
  yet is `:off` and never fails a check (a board may run on Claude Code or
  Codex alone); only a sign-in that is wrong fails. Both leave once a project
  has an agent.

  The classes follow who the AI works for: `:work` (who does the tasks:
  GitHub where they live, the projects, the DeepSeek superagents, Claude Code,
  Codex), `:board_ai` (the board's own refinements, answers and voice turns)
  and `:voice` (speech and listening).
  """

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.{AI, Board, ElevenLabs, GitHub, Runners, Superagents}
  alias AgentBoard.AI.Providers

  @type state :: :ok | :configured | :missing | :off | :failed | :unknown
  @type row :: %{
          id: atom(),
          class: :work | :board_ai | :voice,
          required: boolean(),
          state: state(),
          title: String.t(),
          detail: String.t(),
          fix: map() | nil
        }

  @key_pages %{
    deepseek: "https://platform.deepseek.com/api_keys",
    gemini: "https://aistudio.google.com/apikey",
    openai: "https://platform.openai.com/api-keys",
    github: "https://github.com/settings/tokens",
    elevenlabs: "https://elevenlabs.io/app/settings/api-keys"
  }
  @cli_timeout_ms 8_000

  # What the prototype's install and the agent itself run (its
  # docs/006-deployment.md, Prerequisites), with Homebrew's name for each.
  @agent_tools [
    {"node", "node"},
    {"pnpm", "pnpm"},
    {"git", "git"},
    {"tmux", "tmux"},
    {"python3", "python"},
    {"gh", "gh"}
  ]
  @agent_minimum %{"node" => "22.19.0", "gh" => "2.48.0"}
  @bot_login "mkdir -p ~/.config/gh-agent && GH_CONFIG_DIR=~/.config/gh-agent gh auth login"

  @doc "The rows from configuration only, with no network."
  @spec checklist(keyword()) :: [row()]
  def checklist(opts \\ []), do: rows(:config, opts)

  @doc "The rows proved by each provider's free read. Only on the owner's click."
  @spec verify(keyword()) :: [row()]
  def verify(opts \\ []), do: rows(:live, opts)

  @doc "The first required row that is missing or failing, or nil."
  @spec next_step([row()]) :: row() | nil
  def next_step(rows), do: Enum.find(rows, &(&1.required and &1.state in [:missing, :failed]))

  defp rows(mode, opts) do
    # `:setup_readers` stands in for the outside world in tests, per mode.
    opts =
      Keyword.merge(
        Keyword.get(Application.get_env(:agent_board, :setup_readers, []), mode, []),
        opts
      )

    read = fn key -> Keyword.get_lazy(opts, key, fn -> reader(mode, key) end) end
    agents = read.(:agents).()
    github = read.(:github).()

    [
      github(mode, github),
      projects(read.(:repositories).()),
      agents(mode, agents, read),
      first_agent(mode, agents, github, read),
      cli(mode, "claude", read.(:cli)),
      cli(mode, "codex", read.(:cli)),
      board_ai(mode, read.(:board_ai).(), read),
      voice(mode, read.(:voice).())
    ]
    |> List.flatten()
  end

  # ---- rows ------------------------------------------------------------------

  defp github(mode, value) do
    row = %{id: :github, class: :work, required: true, title: "GitHub"}
    fix = %{href: @key_pages.github, label: gettext("Create a token")}

    case {mode, value} do
      {:config, true} ->
        Map.merge(row, %{state: :configured, detail: gettext("A token is set."), fix: nil})

      {:live, {:ok, login}} ->
        Map.merge(row, %{
          state: :ok,
          detail: gettext("Signed in as @%{login}.", login: login),
          fix: nil
        })

      {_mode, missing} when missing in [false, {:error, :not_configured}] ->
        Map.merge(row, %{
          state: :missing,
          detail: gettext("No token: set GITHUB_TOKEN in .env.local and restart the board."),
          fix: fix
        })

      {:live, {:error, {:http, status}}} when status in [401, 403] ->
        Map.merge(row, %{
          state: :failed,
          detail: gettext("GitHub refused the token: it expired or was revoked."),
          fix: fix
        })

      {:live, _error} ->
        Map.merge(row, %{state: :unknown, detail: gettext("GitHub did not answer."), fix: nil})
    end
  end

  defp projects([]) do
    %{
      id: :projects,
      class: :work,
      required: true,
      title: gettext("Projects"),
      state: :missing,
      detail: gettext("No repository is tracked yet."),
      fix: %{section: "projects", label: gettext("Add a project")}
    }
  end

  defp projects(repositories) do
    %{
      id: :projects,
      class: :work,
      required: true,
      title: gettext("Projects"),
      state: :ok,
      detail:
        ngettext(
          "%{count} repository tracked.",
          "%{count} repositories tracked.",
          length(repositories)
        ),
      fix: nil
    }
  end

  defp agents(_mode, [], read) do
    row = %{
      id: :deepseek_agents,
      class: :work,
      required: false,
      title: gettext("DeepSeek agents")
    }

    case read.(:waiting).() do
      0 ->
        Map.merge(row, %{
          state: :off,
          detail: gettext("No project has its own agent: issues for DeepSeek would not move."),
          fix: %{section: "projects", label: gettext("Create an agent")}
        })

      waiting ->
        Map.merge(row, %{
          state: :off,
          detail:
            ngettext(
              "%{count} agent is installed on this machine, and the board does not follow it yet.",
              "%{count} agents are installed on this machine, and the board does not follow them yet.",
              waiting
            ),
          fix: %{section: "projects", label: gettext("Add it in Projects")}
        })
    end
  end

  defp agents(mode, agents, _read), do: agents(mode, agents)

  # ---- a first agent ---------------------------------------------------------

  defp first_agent(_mode, [_agent | _rest], _github, _read), do: []

  defp first_agent(mode, [], github, read),
    do: [agent_tools(mode, read.(:agent_tools).()), agent_bot(mode, read.(:agent_bot).(), github)]

  defp agent_tools(mode, facts) do
    row = %{
      id: :agent_tools,
      class: :work,
      required: false,
      title: gettext("Tools a DeepSeek agent needs")
    }

    missing = for {tool, :missing} <- facts, do: tool
    old = for {tool, {:old, found, wanted}} <- facts, do: {tool, found, wanted}

    if missing == [] and old == [] do
      Map.merge(row, %{
        state: if(mode == :live, do: :ok, else: :configured),
        detail:
          gettext("%{tools} are on this machine.",
            tools: Enum.map_join(facts, ", ", &elem(&1, 0))
          ),
        fix: nil
      })
    else
      wanted = missing ++ Enum.map(old, &elem(&1, 0))

      Map.merge(row, %{
        state: :off,
        detail: Enum.join(missing_text(missing) ++ Enum.map(old, &old_text/1), " "),
        fix: %{command: "brew install " <> Enum.map_join(wanted, " ", &formula/1)}
      })
    end
  end

  defp missing_text([]), do: []

  defp missing_text(missing),
    do: [gettext("Not on this machine: %{tools}.", tools: Enum.join(missing, ", "))]

  defp old_text({tool, found, wanted}),
    do:
      gettext("%{tool} %{found} is older than the %{wanted} the agent needs.",
        tool: tool,
        found: found,
        wanted: wanted
      )

  defp formula(tool), do: Enum.find_value(@agent_tools, tool, fn {t, f} -> t == tool && f end)

  defp agent_bot(mode, fact, github) do
    row = %{
      id: :agent_bot,
      class: :work,
      required: false,
      title: gettext("The agent's GitHub account")
    }

    case {mode, fact, github} do
      {:config, true, _github} ->
        Map.merge(row, %{
          state: :configured,
          detail: gettext("A GitHub sign-in apart from yours is set up for the agent."),
          fix: nil
        })

      {:live, {:ok, login}, {:ok, login}} ->
        Map.merge(row, %{
          state: :failed,
          detail:
            gettext(
              "It is signed in as %{login}, your own account. The agent must act as an account of its own: everything it writes appears under that name.",
              login: login
            ),
          fix: %{command: @bot_login}
        })

      {:live, {:ok, login}, _github} ->
        Map.merge(row, %{
          state: :ok,
          detail: gettext("Signed in as %{login}.", login: login),
          fix: nil
        })

      {:live, {:error, :logged_out}, _github} ->
        Map.merge(row, %{
          state: :failed,
          detail: gettext("The agent's GitHub sign-in is there, but GitHub refuses it."),
          fix: %{command: @bot_login}
        })

      {_mode, missing, _github} when missing in [false, {:error, :missing}] ->
        Map.merge(row, %{
          state: :off,
          detail:
            gettext(
              "The agent needs a GitHub account of its own, signed in apart from yours. Create the account on GitHub, then sign in as it."
            ),
          fix: %{command: @bot_login}
        })

      {:live, _error, _github} ->
        Map.merge(row, %{
          state: :unknown,
          detail: gettext("The agent's GitHub sign-in could not be read."),
          fix: %{command: @bot_login}
        })
    end
  end

  defp agents(mode, agents) do
    row = %{
      id: :deepseek_agents,
      class: :work,
      required: false,
      title: gettext("DeepSeek agents")
    }

    models = agents |> Enum.map(& &1[:model]) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    model = if models == [], do: gettext("model not read"), else: Enum.join(models, ", ")
    total = length(agents)

    case mode do
      :config ->
        Map.merge(row, %{
          state: :configured,
          detail:
            ngettext("%{count} agent · %{model}", "%{count} agents · %{model}", total,
              model: model
            ),
          fix: nil
        })

      :live ->
        silent = for agent <- agents, agent[:answer] != :ok, do: agent.repository
        answered = total - length(silent)

        if silent == [] do
          Map.merge(row, %{
            state: :ok,
            detail:
              gettext("%{answered} of %{total} answer · %{model}",
                answered: answered,
                total: total,
                model: model
              ),
            fix: nil
          })
        else
          Map.merge(row, %{
            state: :failed,
            detail:
              gettext("%{answered} of %{total} answer; no answer from %{silent}.",
                answered: answered,
                total: total,
                silent: Enum.join(silent, ", ")
              ),
            fix: %{section: "projects", label: gettext("Open Projects")}
          })
        end
    end
  end

  defp cli(mode, executor, read) do
    name = if executor == "claude", do: "Claude Code", else: "Codex"
    login = if executor == "claude", do: "claude auth login", else: "codex login"
    row = %{id: String.to_existing_atom(executor), class: :work, required: false, title: name}

    case {mode, read.(executor)} do
      {:config, true} ->
        Map.merge(row, %{state: :configured, detail: gettext("Installed on this Mac."), fix: nil})

      {:live, :ok} ->
        Map.merge(row, %{state: :ok, detail: gettext("Installed and signed in."), fix: nil})

      {_mode, missing} when missing in [false, {:error, :missing}] ->
        Map.merge(row, %{
          state: :off,
          detail:
            gettext("Not found at %{path}. Install it, or point %{env} in .env.local to it.",
              path: Runners.binary(executor),
              env: String.upcase(executor) <> "_BIN"
            ),
          fix: nil
        })

      {:live, {:error, :logged_out}} ->
        Map.merge(row, %{
          state: :failed,
          detail: gettext("Installed, but not signed in."),
          fix: %{command: login}
        })

      {:live, _error} ->
        Map.merge(row, %{
          state: :unknown,
          detail: gettext("Its login could not be read."),
          fix: %{command: login}
        })
    end
  end

  defp board_ai(mode, ai, read) do
    Map.merge(
      %{id: :board_ai, class: :board_ai, required: true, title: gettext("AI provider")},
      board_ai_state(mode, ai, read)
    )
  end

  defp board_ai_state(_mode, %{provider: nil}, _read) do
    %{
      state: :missing,
      detail:
        gettext(
          "No key: set DEEPSEEK_API_KEY (or GEMINI_API_KEY, OPENAI_API_KEY) in .env.local and restart the board."
        ),
      fix: %{href: @key_pages.deepseek, label: gettext("Get a DeepSeek key")}
    }
  end

  defp board_ai_state(_mode, %{provider: :rehearsal}, _read) do
    %{
      state: :ok,
      detail: gettext("Rehearsal: answers come from local fixtures, no key is used."),
      fix: nil
    }
  end

  defp board_ai_state(mode, %{provider: provider, model: model} = ai, read) do
    label = provider_label(provider)

    fallbacks =
      case ai[:fallbacks] || [] do
        [] ->
          ""

        others ->
          " " <>
            gettext("If it fails: %{others}.",
              others: Enum.map_join(others, ", ", &provider_label/1)
            )
      end

    answers =
      gettext("%{provider} answers (%{model}).", provider: label, model: model) <> fallbacks

    case mode do
      :config ->
        %{state: :configured, detail: answers, fix: nil}

      :live ->
        case read.(:provider_check).(provider) do
          :ok ->
            %{state: :ok, detail: answers, fix: nil}

          {:error, {:http, status}} when status in [401, 403] ->
            %{
              state: :failed,
              detail:
                gettext("%{provider} refused the key: it expired or was revoked.",
                  provider: label
                ),
              fix: %{href: Map.get(@key_pages, provider), label: gettext("Create a key")}
            }

          {:error, _reason} ->
            %{
              state: :unknown,
              detail: gettext("%{provider} did not answer.", provider: label),
              fix: nil
            }
        end
    end
  end

  defp voice(mode, value) do
    row = %{id: :voice, class: :voice, required: false, title: "ElevenLabs"}

    case {mode, value} do
      {:config, true} ->
        Map.merge(row, %{state: :configured, detail: gettext("ElevenLabs key set."), fix: nil})

      {:live, {:ok, %{used: used, limit: limit}}} ->
        Map.merge(row, %{
          state: :ok,
          detail:
            gettext("ElevenLabs answers: %{used} of %{limit} characters used.",
              used: used,
              limit: limit
            ),
          fix: nil
        })

      {_mode, off} when off in [false, {:error, :not_configured}] ->
        Map.merge(row, %{
          state: :off,
          detail:
            gettext("No ElevenLabs key: the board speaks and listens with the browser, free."),
          fix: %{
            href: @key_pages.elevenlabs,
            label: gettext("Get an ElevenLabs key")
          }
        })

      {:live, {:error, :auth_expired}} ->
        Map.merge(row, %{
          state: :failed,
          detail: gettext("ElevenLabs refused the key: it expired or was revoked."),
          fix: %{
            href: @key_pages.elevenlabs,
            label: gettext("Create a key")
          }
        })

      {:live, _error} ->
        Map.merge(row, %{state: :unknown, detail: gettext("ElevenLabs did not answer."), fix: nil})
    end
  end

  defp provider_label(id) do
    case Providers.fetch(id) do
      {:ok, %{label: label}} -> label
      :error -> to_string(id)
    end
  end

  # ---- readers ---------------------------------------------------------------

  defp reader(_mode, :repositories),
    do: fn -> Enum.map(Board.list_repositories(), &"#{&1.owner}/#{&1.name}") end

  defp reader(_mode, :board_ai), do: &AI.answering/0
  defp reader(_mode, :provider_check), do: &provider_models/1

  defp reader(:config, :github), do: &GitHub.configured?/0
  defp reader(:config, :agents), do: fn -> Enum.map(Superagents.list(), &agent_fact/1) end
  defp reader(:config, :cli), do: &executable?/1
  defp reader(:config, :voice), do: &ElevenLabs.configured?/0

  defp reader(:live, :github), do: &GitHub.login/0

  defp reader(:live, :agents) do
    fn ->
      manager = Superagents.Manager.impl()
      Enum.map(Superagents.list(), &Map.put(agent_fact(&1), :answer, answer(manager, &1)))
    end
  end

  defp reader(_mode, :waiting), do: fn -> length(Superagents.unregistered()) end

  defp reader(:config, :agent_tools),
    do: fn -> for({tool, _formula} <- @agent_tools, do: {tool, found(tool)}) end

  defp reader(:live, :agent_tools),
    do: fn -> for({tool, _formula} <- @agent_tools, do: {tool, recent(tool)}) end

  defp reader(:config, :agent_bot), do: &Superagents.Bot.signed_in?/0
  defp reader(:live, :agent_bot), do: &Superagents.Bot.login/0

  defp reader(:live, :cli), do: &cli_login/1
  defp reader(:live, :voice), do: &ElevenLabs.subscription/0

  defp answer(manager, superagent) do
    case manager.status(superagent) do
      {:ok, _observation} -> :ok
      error -> error
    end
  end

  defp agent_fact(superagent) do
    %{
      repository:
        superagent.repository && "#{superagent.repository.owner}/#{superagent.repository.name}",
      model: Superagents.profile_model(superagent)
    }
  end

  # Listing models is free on all three providers; a completion would be a paid call.
  defp provider_models(id) do
    with {:ok, %{base_url: base_url}} <- Providers.fetch(id),
         {:ok, %Req.Response{status: 200}} <-
           Req.get(base_url <> "/models", auth: {:bearer, Providers.key(id)}, retry: false) do
      :ok
    else
      {:ok, %Req.Response{status: status}} -> {:error, {:http, status}}
      :error -> {:error, :unknown_provider}
      {:error, reason} -> {:error, reason}
    end
  rescue
    exception -> {:error, exception}
  end

  defp executable?(executor) do
    case File.stat(Runners.binary(executor)) do
      {:ok, %File.Stat{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _ -> false
    end
  end

  # The login commands print the account (an e-mail): only the verdict is kept.
  defp cli_login(executor) do
    if executable?(executor), do: login_status(executor), else: {:error, :missing}
  end

  defp login_status(executor) do
    args = if executor == "claude", do: ["auth", "status"], else: ["login", "status"]

    task =
      Task.async(fn ->
        # The binary is the owner's own CLAUDE_BIN/CODEX_BIN, as bot_access runs gh.
        System.cmd("/usr/bin/env", [Runners.binary(executor) | args], stderr_to_stdout: true)
      end)

    case Task.yield(task, @cli_timeout_ms) || Task.shutdown(task) do
      {:ok, {output, 0}} -> if logged_in?(executor, output), do: :ok, else: {:error, :logged_out}
      {:ok, {_output, _status}} -> {:error, :logged_out}
      nil -> {:error, :timeout}
    end
  rescue
    exception -> {:error, exception}
  end

  # ---- a first agent's readers -----------------------------------------------

  defp found(tool), do: if(System.find_executable(tool), do: :ok, else: :missing)

  # Only the tools with a floor are run; a version that cannot be read is not
  # a reason to stop the owner.
  defp recent(tool) do
    with path when is_binary(path) <- System.find_executable(tool) || :missing,
         wanted when is_binary(wanted) <- Map.get(@agent_minimum, tool, :ok),
         {:ok, {output, 0}} <- timed(path, ["--version"], []),
         [found] <- Regex.run(~r/\d+\.\d+\.\d+/, output),
         :lt <- Version.compare(found, wanted) do
      {:old, found, wanted}
    else
      :missing -> :missing
      _fine_or_unread -> :ok
    end
  end

  # `command` is a path `System.find_executable/1` answered for a tool this
  # module names; no request reaches it. Run through env, as the CLIs above.
  defp timed(command, args, env) do
    task =
      Task.async(fn ->
        System.cmd("/usr/bin/env", [command | args], env: env, stderr_to_stdout: true)
      end)

    Task.yield(task, @cli_timeout_ms) || Task.shutdown(task)
  end

  defp logged_in?("claude", output) do
    case Jason.decode(output) do
      {:ok, %{"loggedIn" => true}} -> true
      _ -> false
    end
  end

  # "Not logged in" also contains "logged in": the verdict starts the line.
  defp logged_in?("codex", output), do: output =~ ~r/^\s*logged in/im
end
