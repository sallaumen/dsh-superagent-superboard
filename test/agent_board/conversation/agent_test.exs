defmodule AgentBoard.Conversation.AgentTest do
  @moduledoc """
  One spoken turn: a local yes/no, the model's chosen action, the proposal
  that waits for a spoken yes, and the write that happens once.
  """
  use AgentBoard.DataCase, async: false

  # Failures are exercised on purpose; their log lines show only if a test fails.
  @moduletag capture_log: true

  alias AgentBoard.{Actions, Board, Conversation, Repo}
  alias AgentBoard.AI.Engines.Scripted
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
          "repository" => "",
          "lookup" => "",
          "direct" => false,
          "executor" => ""
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

  test "a task the owner sends to Claude Code says so, and its issue has no mention",
       %{repo: repo} do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:issue, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "number" => 77,
        "html_url" => "https://github.com/sallaumen/arena-rogue/issues/77"
      })
    end)

    script(fn %{name: :voice_agent} ->
      agent_answer("create_task", %{
        "request" => "refazer o placar",
        "title" => "Refazer o placar",
        "details" => ["o placar cabe na tela do celular"],
        "repository" => "arena rogue",
        "executor" => "claude"
      })
    end)

    proposed = turn("Manda pro Claude refazer o placar do arena rogue", repo)

    assert proposed.reply ==
             "Criar no arena-rogue a tarefa “Refazer o placar” para o Claude Code? " <>
               "O board abre com o rótulo executor:claude; nada começa sozinho."

    turn("Sim.", repo)

    assert_received {:issue, sent}
    refute sent["body"] =~ "@sallaumen-agent"
    assert sent["labels"] == ["executor:claude"]

    task = Repo.get_by!(Task, repository_id: repo.id, number: 77)
    assert task.executor == "claude"

    assert %AgentBoard.Routing.Decision{
             chosen: "claude",
             suggested: "claude",
             decided_by: "voice"
           } =
             Repo.get_by!(AgentBoard.Routing.Decision, task_id: task.id)
  end

  test "a voice task without a named executor goes where the router suggests", %{repo: repo} do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:issue, Jason.decode!(body)})
      Req.Test.json(conn, %{"number" => 78, "html_url" => "https://github.com/x/y/issues/78"})
    end)

    script(fn %{name: :voice_agent} ->
      agent_answer("create_task", %{
        "request" => "mostrar o placar",
        "title" => "Mostrar o placar",
        "details" => ["o placar aparece"],
        "repository" => "arena rogue"
      })
    end)

    turn("Cria uma tarefa no arena rogue pra mostrar o placar", repo)
    turn("Sim.", repo)

    # No orchestrator answers in the test: the runner stays the board's
    # default, and its issue carries the mention it acts on.
    assert_received {:issue, sent}
    assert sent["body"] =~ ~r/@sallaumen-agent\z/
    assert sent["labels"] == ["executor:dsh"]

    task = Repo.get_by!(Task, repository_id: repo.id, number: 78)

    assert %AgentBoard.Routing.Decision{chosen: "dsh", suggested: "dsh", decided_by: "voice"} =
             decision = Repo.get_by!(AgentBoard.Routing.Decision, task_id: task.id)

    refute Enum.any?(decision.reasons, &(&1 =~ "Você pediu"))
  end

  test "yes and no are recognized locally, long sentences are not" do
    assert Agent.yes_or_no("Sim, pode criar!") == :yes
    assert Agent.yes_or_no("pode") == :yes
    assert Agent.yes_or_no("Não, deixa pra lá.") == :no
    assert Agent.yes_or_no("não sei, o que você acha?") == :none
    assert Agent.yes_or_no("sim mas antes me diz quantas tarefas estão rodando agora") == :none
    assert Agent.yes_or_no("") == :none
  end

  test "a yes is every word affirmative or filler, a no word anywhere is a no" do
    for yes <- [
          "sim",
          "pode criar",
          "manda ver",
          "ok, valeu",
          "sim, por favor",
          "pode sim, obrigado",
          "yes please",
          "go ahead, thanks",
          "do it"
        ] do
      assert {yes, Agent.yes_or_no(yes)} == {yes, :yes}
    end

    for no <- [
          "pode cancelar",
          "ok cancela",
          "isso não",
          "no thanks",
          "yes, cancel it",
          "not now"
        ] do
      assert {no, Agent.yes_or_no(no)} == {no, :no}
    end

    for neither <- [
          "pode deixar",
          "manda pro Claude",
          "cria outra tarefa sobre login",
          "valeu",
          "por favor",
          "cria no colmex",
          "go ahead with login"
        ] do
      assert {neither, Agent.yes_or_no(neither)} == {neither, :none}
    end
  end

  defp running_task(repo) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      number: 7,
      title: "Placar",
      state: "running",
      kind: "issue"
    })
    |> Repo.insert!()
  end

  test "pode cancelar answers a stop with a no: the issue stays open", %{repo: repo} do
    task = running_task(repo)
    Req.Test.stub(@stub, fn _conn -> flunk("nothing may reach GitHub") end)
    script(fn %{name: :voice_agent} -> agent_answer("stop_task", %{"task_number" => 7}) end)
    turn("para a tarefa sete", repo)

    script(fn _ -> flunk("a no is local") end)
    assert %{action: "cancel"} = turn("pode cancelar", repo)
    assert %Task{stopped: false} = Repo.get!(Task, task.id)
    assert Conversation.pending_proposal() == nil
  end

  test "a yes after another turn confirms nothing, even if the model reads a confirm",
       %{repo: repo} do
    task = running_task(repo)
    Req.Test.stub(@stub, fn _conn -> flunk("nothing may reach GitHub") end)
    script(fn %{name: :voice_agent} -> agent_answer("stop_task", %{"task_number" => 7}) end)
    turn("para a tarefa sete", repo)

    script(fn %{name: :voice_agent} -> agent_answer("reply", %{"reply" => "Três rodando."}) end)
    turn("quantas tarefas estão rodando?", repo)
    assert Conversation.pending_proposal() == nil

    script(fn %{name: :voice_agent} -> agent_answer("confirm", %{"reply" => "De nada."}) end)
    assert %{reply: "De nada."} = turn("ok, valeu", repo)
    assert %Task{stopped: false} = Repo.get!(Task, task.id)
  end

  test "repete says the proposal again and keeps it waiting for the yes", %{repo: repo} do
    running_task(repo)
    script(fn %{name: :voice_agent} -> agent_answer("stop_task", %{"task_number" => 7}) end)
    turn("para a tarefa sete", repo)

    turn("repete", repo)
    assert %Turn{proposal: %{"kind" => "stop_task"}} = Conversation.pending_proposal()
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

    # The proposal says the registry's sentence, the one the screen shows.
    assert proposed.reply ==
             "Criar no arena-rogue a tarefa “Mostrar o volume da voz no cabeçalho”? " <>
               "O board abre a issue no GitHub e o agente começa sozinho."

    assert %Turn{proposal: %{"kind" => "create_task"}} = Conversation.pending_proposal()
    # One model call refines it: no second, slower refine call.
    assert_received {:called, :voice_agent}
    refute_received {:called, :refine_request}

    created = turn("Sim, pode.", repo)
    assert created.reply == "Pronto. A tarefa 42 entrou na fila do arena-rogue."
    assert Elixir.Agent.get(counter, & &1) == 42

    # The yes is a recorded decision: confirmed by the owner, by voice, on that sentence.
    assert [%{action: "create_tasks", decision: "confirmed", by: "owner", via: "voice"} = d] =
             Actions.recent(1)

    assert d.evidence == "phrase" and d.phrase == proposed.reply and d.outcome == "ok"

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

    assert result.reply ==
             "Parar a tarefa #7, “Placar”? O board fecha a issue e marca a tarefa como parada; " <>
               "um passo que o agente já começou termina antes."

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

  test "forget asks first (there is no way back), then clears the memory", %{repo: repo} do
    script(fn %{name: :voice_agent} -> agent_answer("forget") end)

    proposed = turn("esquece tudo", repo)

    assert proposed.reply ==
             "Esquecer toda a conversa por voz? O agente perde o contexto, e não há como desfazer."

    assert proposed.listen
    assert length(Conversation.context().turns) == 2

    assert %{reply: "Pronto, esqueci a nossa conversa. Começando do zero."} = turn("sim", repo)
    assert [%{role: "agent"}] = Conversation.context().turns
  end

  test "the model's direct flag without the owner's words still asks", %{repo: repo} do
    Req.Test.stub(@stub, fn _conn -> flunk("GitHub must not be called before a yes") end)

    script(fn %{name: :voice_agent} ->
      agent_answer("create_task", %{
        "request" => "corrigir o botão",
        "title" => "Corrigir o botão",
        "direct" => true
      })
    end)

    proposed = turn("corrige o botão de salvar", repo)

    assert proposed.listen
    assert proposed.reply =~ "Criar no arena-rogue a tarefa “Corrigir o botão”?"
    assert %Turn{proposal: %{"kind" => "create_task"}} = Conversation.pending_proposal()
  end

  test "a yes to a task that changed since the question is refused", %{repo: repo} do
    Req.Test.stub(@stub, fn _conn -> flunk("GitHub must not be called") end)

    {:ok, task} =
      %Task{}
      |> Task.changeset(%{repository_id: repo.id, number: 9, title: "Placar", kind: "issue"})
      |> Repo.insert()

    script(fn %{name: :voice_agent} -> agent_answer("stop_task", %{"task_number" => 9}) end)
    turn("para a nove", repo)

    # The sync renamed it between the question and the yes.
    task |> Ecto.Changeset.change(title: "Placar novo") |> Repo.update!()

    assert %{reply: "Não fiz nada: algo mudou desde que perguntei. Peça de novo."} =
             turn("sim", repo)

    refute Repo.get!(Task, task.id).stopped

    assert [%{action: "stop_task", decision: "refused", detail: "phrase_changed"}] =
             Actions.recent(1)
  end

  test "a spoken no is a refusal by the owner", %{repo: repo} do
    {:ok, _task} =
      %Task{}
      |> Task.changeset(%{repository_id: repo.id, number: 10, title: "Placar", kind: "issue"})
      |> Repo.insert()

    script(fn %{name: :voice_agent} -> agent_answer("archive_task", %{"task_number" => 10}) end)
    turn("arquiva a dez", repo)

    assert %{reply: "Tudo bem, deixei pra lá."} = turn("não", repo)

    assert [%{action: "archive_task", decision: "refused", detail: "declined", by: "owner"}] =
             Actions.recent(1)
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
             "Perguntar ao agente na tarefa #12: “Você já rodou os testes?” " <>
               "O board comenta na issue do GitHub."

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
