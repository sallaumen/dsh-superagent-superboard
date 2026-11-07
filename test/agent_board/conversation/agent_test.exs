defmodule AgentBoard.Conversation.AgentTest do
  @moduledoc """
  One spoken turn: a local yes/no, the model's chosen action, the proposal
  that waits for a spoken yes, and the write that happens once.
  """
  use AgentBoard.DataCase, async: false

  # Failures are exercised on purpose; their log lines show only if a test fails.
  @moduletag capture_log: true

  alias AgentBoard.AI.Engines.Scripted
  alias AgentBoard.{Board, Conversation, Repo}
  alias AgentBoard.Board.Task
  alias AgentBoard.Conversation.{Agent, Turn}

  @stub AgentBoard.Conversation.AgentTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    previous =
      for key <- [:ai_rehearsal, :ai_engine, :ai_api_key, :ai_script, :github_client],
          into: %{},
          do: {key, Application.get_env(:agent_board, key)}

    Application.put_env(:agent_board, :ai_rehearsal, false)
    Application.put_env(:agent_board, :ai_engine, Scripted)
    Application.put_env(:agent_board, :ai_api_key, "test-key")

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:agent_board, key),
          else: Application.put_env(:agent_board, key, value)
      end
    end)

    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    %{repo: repo}
  end

  defp script(fun), do: Application.put_env(:agent_board, :ai_script, fun)

  defp agent_answer(action, fields \\ %{}) do
    Scripted.answer(
      Map.merge(
        %{
          "reply" => "",
          "action" => action,
          "request" => "",
          "title" => "",
          "details" => [],
          "question" => "",
          "task_number" => 0,
          "repository" => ""
        },
        fields
      )
    )
  end

  defp ctx(repo, extra) do
    Map.merge(
      %{
        language: "pt-BR",
        repo: repo,
        repos: Board.list_repositories(),
        board: %{},
        sync_event: nil,
        open_task: nil,
        client: AgentBoard.GitHub.client()
      },
      extra
    )
  end

  defp turn(text, repo, extra \\ %{}) do
    {:ok, _} = Conversation.record("owner", text, repository_id: repo.id)
    Agent.respond(text, ctx(repo, extra))
  end

  defp github_issues do
    {:ok, counter} = Elixir.Agent.start_link(fn -> 41 end)

    Req.Test.stub(@stub, fn conn ->
      number = Elixir.Agent.get_and_update(counter, &{&1 + 1, &1 + 1})

      Req.Test.json(conn, %{
        "number" => number,
        "html_url" => "https://github.com/sallaumen/arena-rogue/issues/#{number}"
      })
    end)

    counter
  end

  test "yes and no are recognized locally, long sentences are not" do
    assert Agent.yes_or_no("Sim, pode criar!") == :yes
    assert Agent.yes_or_no("pode") == :yes
    assert Agent.yes_or_no("Não, deixa pra lá.") == :no
    assert Agent.yes_or_no("não sei, o que você acha?") == :none
    assert Agent.yes_or_no("sim mas antes me diz quantas tarefas estão rodando agora") == :none
    assert Agent.yes_or_no("") == :none
  end

  test "a chat turn is answered with the model's reply and remembered", %{repo: repo} do
    script(fn %{name: :voice_agent} ->
      agent_answer("reply", %{"reply" => "Tudo tranquilo por aqui."})
    end)

    assert %{reply: "Tudo tranquilo por aqui.", listen: false} = turn("Oi, tudo bem?", repo)

    assert [%{role: "owner"}, %{role: "agent", text: "Tudo tranquilo por aqui."}] =
             Conversation.context().turns
  end

  test "the model sees the memory, the waiting proposal and the board", %{repo: repo} do
    test_pid = self()

    script(fn %{name: :voice_agent, prompt: prompt} ->
      send(test_pid, {:prompt, prompt})
      agent_answer("reply", %{"reply" => "Ok."})
    end)

    {:ok, _} = Conversation.record("agent", "Antes conversamos sobre o placar.")
    turn("E aí?", repo, %{board: %{running: [%{number: 7, title: "Placar", state: "running"}]}})

    assert_received {:prompt, prompt}
    assert prompt =~ "Antes conversamos sobre o placar."
    assert prompt =~ "Placar"
    assert prompt =~ "pt-BR"
    assert prompt =~ "sallaumen/arena-rogue"
  end

  test "a request for work is refined, proposed, and created once on a spoken yes", %{repo: repo} do
    counter = github_issues()
    test_pid = self()

    script(fn %{name: name} ->
      send(test_pid, {:called, name})

      agent_answer("create_task", %{
        "reply" => "Claro.",
        "request" => "mostrar o volume da voz no cabeçalho",
        "title" => "Mostrar o volume da voz no cabeçalho",
        "details" => ["o volume aparece em porcentagem", "sem mudar o layout"],
        "repository" => "arena rogue"
      })
    end)

    proposed =
      turn("Oi Claude, cria uma tarefa no arena rogue pra mostrar o volume, obrigado", repo)

    assert proposed.listen

    assert proposed.reply =~
             "Vou criar no arena-rogue a tarefa: Mostrar o volume da voz no cabeçalho"

    assert proposed.reply =~ "Posso criar?"
    assert %Turn{proposal: %{"kind" => "create_task"}} = Conversation.pending_proposal()
    # One model call refines it: no second, slower refine call.
    assert_received {:called, :voice_agent}
    refute_received {:called, :refine_request}

    created = turn("Sim, pode.", repo)
    assert created.reply == "Pronto. A tarefa 42 entrou na fila do arena-rogue."
    assert Elixir.Agent.get(counter, & &1) == 42

    task = Repo.get_by!(Task, repository_id: repo.id, number: 42)
    assert task.title == "Mostrar o volume da voz no cabeçalho"
    assert task.body =~ "**Critérios de aceite**"
    assert task.body =~ "- sem mudar o layout"
    assert task.body =~ "Pedido por voz"

    # A second yes has nothing waiting: it goes to the model, nothing is created.
    script(fn %{name: :voice_agent} -> agent_answer("reply", %{"reply" => "Já está feito."}) end)
    assert %{reply: "Já está feito."} = turn("sim", repo)
    assert Elixir.Agent.get(counter, & &1) == 42
  end

  test "a proposal is settled once, whoever answers first", %{repo: repo} do
    {:ok, turn} =
      Conversation.record("agent", "Posso criar?",
        repository_id: repo.id,
        proposal: %{"kind" => "create_task"}
      )

    assert Conversation.settle(turn, "confirmed") == :ok
    assert Conversation.settle(turn, "confirmed") == :already_settled
    assert Conversation.settle(turn, "cancelled") == :already_settled
  end

  test "a no cancels the waiting proposal without creating anything", %{repo: repo} do
    Req.Test.stub(@stub, fn _conn -> flunk("GitHub must not be called") end)

    {:ok, _} =
      Conversation.record("agent", "Posso criar?",
        repository_id: repo.id,
        proposal: %{
          "kind" => "create_task",
          "repository_id" => repo.id,
          "title" => "x",
          "body" => "y"
        }
      )

    assert %{reply: "Tudo bem, deixei pra lá."} = turn("não, deixa", repo)
    assert Conversation.pending_proposal() == nil
  end

  test "an old proposal expires instead of being confirmed", %{repo: repo} do
    {:ok, turn} =
      Conversation.record("agent", "Posso criar?",
        repository_id: repo.id,
        proposal: %{"kind" => "create_task"}
      )

    later = DateTime.add(turn.inserted_at, 11 * 60, :second)
    assert Conversation.pending_proposal(later) == nil
    assert Repo.get!(Turn, turn.id).proposal_status == "expired"
  end

  test "an unclear request becomes a question, not a proposal", %{repo: repo} do
    script(fn %{name: :voice_agent} ->
      agent_answer("create_task", %{
        "request" => "melhora o placar",
        "question" => "Qual placar, o da partida ou o geral?"
      })
    end)

    result = turn("melhora o placar", repo)
    assert result.reply == "Antes de criar, uma dúvida: Qual placar, o da partida ou o geral?"
    assert result.listen
    assert Conversation.pending_proposal() == nil
  end

  test "a request without any project asks where it goes" do
    script(fn %{name: :voice_agent} -> agent_answer("create_task", %{"request" => "algo"}) end)

    {:ok, _} = Conversation.record("owner", "cria uma tarefa")

    result =
      Agent.respond("cria uma tarefa", %{language: "pt-BR", repo: nil, repos: [], board: %{}})

    assert result.reply == "Claro. Em qual projeto eu coloco essa tarefa?"
  end

  test "stop asks before acting and names the task", %{repo: repo} do
    {:ok, task} =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        number: 7,
        title: "Placar",
        state: "running",
        kind: "issue"
      })
      |> Repo.insert()

    script(fn %{name: :voice_agent} -> agent_answer("stop_task", %{"task_number" => 7}) end)

    result = turn("para a tarefa sete", repo)
    assert result.reply == "Parar a tarefa 7, Placar? Posso?"

    assert %Turn{proposal: %{"kind" => "stop_task", "task_id" => id}} =
             Conversation.pending_proposal()

    assert id == task.id
  end

  test "a model failure is said, never raised", %{repo: repo} do
    script(fn %{name: :voice_agent} -> {:error, :usage_limit} end)
    # Every provider failed: the board says it could not think, in words.
    assert %{reply: "Não consegui pensar nisso agora. Tenta de novo em um instante."} =
             turn("oi", repo)
  end

  test "a spoken project name matches the tracked repository", %{repo: repo} do
    assert Agent.match_repository([repo], "Arena Rogue") == repo
    assert Agent.match_repository([repo], "sallaumen/arena-rogue") == repo
    assert Agent.match_repository([repo], "outro") == nil
  end

  test "forget clears the memory", %{repo: repo} do
    script(fn %{name: :voice_agent} -> agent_answer("forget") end)

    assert %{reply: "Pronto, esqueci a nossa conversa. Começando do zero."} =
             turn("esquece tudo", repo)

    assert [%{role: "agent"}] = Conversation.context().turns
  end

  test "asking the coding agent waits for a yes, then posts the question once", %{repo: repo} do
    {:ok, task} =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        number: 12,
        title: "Placar",
        state: "running",
        kind: "issue"
      })
      |> Repo.insert()

    {:ok, posts} = Elixir.Agent.start_link(fn -> 0 end)

    Req.Test.stub(@stub, fn conn ->
      Elixir.Agent.update(posts, &(&1 + 1))
      Req.Test.json(conn, %{"id" => 9001, "user" => %{"login" => "sallaumen"}})
    end)

    script(fn %{name: :voice_agent} ->
      agent_answer("ask_task", %{"task_number" => 12, "request" => "Você já rodou os testes?"})
    end)

    proposed = turn("pergunta pro agente da doze se ele já rodou os testes", repo)

    assert proposed.reply ==
             "Vou perguntar ao agente na tarefa 12: Você já rodou os testes? Posso mandar?"

    assert proposed.listen
    assert Elixir.Agent.get(posts, & &1) == 0

    assert %{reply: "Mandei. A resposta vai aparecer na conversa da tarefa 12."} =
             turn("pode", repo)

    assert Elixir.Agent.get(posts, & &1) == 1

    comment = Repo.get_by!(AgentBoard.Board.Comment, task_id: task.id, kind: "user")
    assert comment.body =~ "Você já rodou os testes?"
    assert comment.body =~ "@sallaumen-agent"
  end

  test "repete says the last reply again without the model", %{repo: repo} do
    script(fn _ -> flunk("the model must not be called") end)
    {:ok, _} = Conversation.record("agent", "Duas tarefas rodando.")

    assert %{reply: "Duas tarefas rodando.", action: "repeat"} = turn("Pode repetir?", repo)
  end

  test "mais devagar and mais alto change the voice without the model", %{repo: repo} do
    script(fn _ -> flunk("the model must not be called") end)

    assert %{reply: "Pronto, mais devagar.", effect: :voice_changed} =
             turn("Fala mais devagar", repo)

    assert AgentBoard.Voice.speed() == 0.9

    :ok = AgentBoard.Voice.put_volume(90)
    assert %{reply: "Pronto, mais alto."} = turn("mais alto", repo)
    assert AgentBoard.Voice.volume() == 100
    assert %{reply: "O volume já está no máximo."} = turn("mais alto", repo)
  end

  test "a long sentence about speed is a request for the model, not a voice change", %{repo: repo} do
    script(fn %{name: :voice_agent} -> agent_answer("reply", %{"reply" => "Entendi."}) end)

    assert %{reply: "Entendi."} =
             turn("cria uma tarefa para deixar o jogo mais rápido no fim", repo)

    assert AgentBoard.Voice.speed() == 1.0
  end
end
