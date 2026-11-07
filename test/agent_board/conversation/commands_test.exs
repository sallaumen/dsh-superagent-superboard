defmodule AgentBoard.Conversation.CommandsTest do
  @moduledoc """
  The voice commands beyond chat: the instant local ones, the reads that
  look the board up and answer from its facts, the direct create and its
  undo, and the catalog the owner sees.
  """
  use AgentBoard.DataCase, async: false

  @moduletag capture_log: true

  alias AgentBoard.AI.Engines.Scripted
  alias AgentBoard.AI.Registry
  alias AgentBoard.{Board, Conversation, Repo}
  alias AgentBoard.Board.{Comment, PullRequest, Task}
  alias AgentBoard.Conversation.{Agent, Lookup}
  alias AgentBoard.Voice.Commands

  @stub AgentBoard.Conversation.CommandsTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    previous =
      for key <- [:ai_rehearsal, :ai_engine, :ai_api_key, :ai_script, :github_client, :state_db],
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

  defp agent_answer(action, fields) do
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
          "direct" => false
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

  defp task!(repo, attrs) do
    %Task{}
    |> Task.changeset(Map.merge(%{repository_id: repo.id, kind: "issue", state: "queued"}, attrs))
    |> Repo.insert!()
  end

  # The facts the explain call received, decoded from its prompt.
  defp explained(test_pid, reply) do
    fn %{name: :voice_explain, prompt: "Inputs:\n" <> json} ->
      send(test_pid, {:explain, Jason.decode!(json)})
      Scripted.answer(%{"reply" => reply})
    end
  end

  describe "instant commands" do
    test "status answers from the exact lane totals without the model", %{repo: repo} do
      script(fn _ -> flunk("the model must not be called") end)
      board = %{running: [%{number: 1}], task_counts: %{running: 3, blocked: 1}}

      assert %{action: "status", reply: reply} = turn("Status", repo, %{board: board})
      assert reply =~ "3 em andamento"
      assert reply =~ "1 "
    end

    test "ajuda opens the list without the model", %{repo: repo} do
      script(fn _ -> flunk("the model must not be called") end)

      assert %{action: "help", effect: :show_commands, reply: reply} =
               turn("O que eu posso pedir?", repo)

      assert reply =~ "A lista completa está na tela."
    end
  end

  describe "reads that look the board up" do
    test "why a task is blocked: the explain call gets its workpad, run and PR", %{repo: repo} do
      test_pid = self()

      task =
        task!(repo, %{
          number: 42,
          title: "Corrigir o placar",
          state: "blocked",
          body: "O placar zera."
        })

      Repo.insert!(%Comment{
        task_id: task.id,
        github_id: 1,
        author: "sallaumen-agent",
        kind: "agent",
        body: "## Relatório do agente\n\n### Bloqueio\nFalta a chave do serviço de placar."
      })

      script(fn
        %{name: :voice_agent} -> agent_answer("look", %{"lookup" => "task", "task_number" => 42})
        request -> explained(test_pid, "A 42 está bloqueada esperando a chave.").(request)
      end)

      result = turn("Por que a 42 está bloqueada?", repo)

      assert result.reply == "A 42 está bloqueada esperando a chave."
      assert result.action == "look_task"
      assert {:open_task, %Task{number: 42}} = result.effect

      assert_received {:explain, %{"lookup" => "task", "question" => question, "facts" => facts}}
      assert question == "Por que a 42 está bloqueada?"
      assert facts["title"] == "Corrigir o placar"
      assert facts["state"] == "blocked"
      assert facts["workpad"]["blockage"] =~ "Falta a chave"
      assert is_integer(facts["in_state_minutes"])
    end

    test "an unknown task is said without the explain call", %{repo: repo} do
      script(fn
        %{name: :voice_agent} -> agent_answer("look", %{"lookup" => "task", "task_number" => 99})
        %{name: :voice_explain} -> flunk("nothing to explain")
      end)

      assert %{reply: "Não achei a tarefa 99 neste projeto."} = turn("como está a 99?", repo)
    end

    test "search folds accents and ranks title hits first", %{repo: repo} do
      test_pid = self()
      task!(repo, %{number: 5, title: "Corrigir o botão de salvar"})
      task!(repo, %{number: 6, title: "Placar", body: "o botao some no celular"})
      task!(repo, %{number: 7, title: "Outra coisa"})

      script(fn
        %{name: :voice_agent} ->
          agent_answer("look", %{"lookup" => "search", "request" => "botao"})

        request ->
          explained(test_pid, "Achei duas.").(request)
      end)

      assert %{reply: "Achei duas."} = turn("acha a tarefa do botao", repo)

      assert_received {:explain, %{"facts" => facts}}
      assert Enum.map(facts["tasks"], & &1["number"]) == [5, 6]
      assert facts["searched_words"] == ["botao"]
    end

    test "a search without words asks what to search", %{repo: repo} do
      script(fn
        %{name: :voice_agent} -> agent_answer("look", %{"lookup" => "search"})
        %{name: :voice_explain} -> flunk("nothing to explain")
      end)

      assert %{reply: "Claro. Procuro o quê?", listen: true} = turn("acha a tarefa", repo)
    end

    test "failures list the red CI of open pull requests", %{repo: repo} do
      test_pid = self()

      Repo.insert!(%PullRequest{
        repository_id: repo.id,
        number: 77,
        title: "Novo placar",
        state: "open",
        checks_state: "failure",
        checks_failed: "test"
      })

      Repo.insert!(%PullRequest{
        repository_id: repo.id,
        number: 78,
        title: "Verde",
        state: "open",
        checks_state: "success"
      })

      script(fn
        %{name: :voice_agent} -> agent_answer("look", %{"lookup" => "failures"})
        request -> explained(test_pid, "O PR 77 está vermelho no teste.").(request)
      end)

      assert %{reply: "O PR 77 está vermelho no teste."} = turn("o que está falhando?", repo)

      assert_received {:explain, %{"facts" => facts}}
      assert [%{"number" => 77, "failed_checks" => "test"}] = facts["failing_checks"]
    end

    test "runs read the runner's tickets: last report and what ended", %{repo: repo} do
      test_pid = self()
      now = DateTime.utc_now()

      task!(repo, %{
        number: 9,
        title: "Som",
        state: "running",
        started_at: DateTime.add(now, -1800)
      })

      with_tickets([
        %{
          "title" => "Som",
          "mandate" => %{"basis" => %{"scope" => %{"number" => 9}}},
          "assignments" => [
            %{
              "state" => "running",
              "report" => %{
                "state" => "progress",
                "summary" => "Rodando os testes",
                "at" => DateTime.to_iso8601(now)
              }
            }
          ]
        },
        %{
          "title" => "Antiga",
          "mandate" => %{"basis" => %{"scope" => %{"number" => 3}}},
          "ended" => %{
            "outcome" => "merged",
            "at" => DateTime.to_iso8601(DateTime.add(now, -600))
          }
        }
      ])

      board = %{running: Board.task_page(repo.id, :running, nil, 8), task_counts: %{running: 1}}

      script(fn
        %{name: :voice_agent} -> agent_answer("look", %{"lookup" => "runs"})
        request -> explained(test_pid, "Uma rodando, a 9.").(request)
      end)

      assert %{reply: "Uma rodando, a 9."} = turn("o que está rodando?", repo, %{board: board})

      assert_received {:explain, %{"facts" => facts}}
      assert [%{"number" => 9, "running_minutes" => minutes, "run" => run}] = facts["running"]
      assert minutes in 29..31
      assert run["report_summary"] == "Rodando os testes"
      assert [%{"numbers" => [3], "outcome" => "merged"}] = facts["ended_last_24h"]
    end

    test "activity counts today's merges and new tasks", %{repo: repo} do
      test_pid = self()

      Repo.insert!(%PullRequest{
        repository_id: repo.id,
        number: 50,
        title: "Merge de hoje",
        state: "merged",
        merged_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      task!(repo, %{number: 51, title: "Nova"})

      script(fn
        %{name: :voice_agent} -> agent_answer("look", %{"lookup" => "activity"})
        request -> explained(test_pid, "Hoje entrou um merge.").(request)
      end)

      assert %{reply: "Hoje entrou um merge."} = turn("o que mudou hoje?", repo)

      assert_received {:explain, %{"facts" => %{"today" => today, "last_7_days" => week}}}
      assert today["merged"]["count"] == 1
      assert today["created"]["count"] == 1
      assert week["merged_count"] == 1
    end

    test "an explain failure is said, never raised", %{repo: repo} do
      script(fn
        %{name: :voice_agent} -> agent_answer("look", %{"lookup" => "failures"})
        %{name: :voice_explain} -> {:error, :usage_limit}
      end)

      assert %{reply: "Não consegui pensar nisso agora. Tenta de novo em um instante."} =
               turn("o que está falhando?", repo)
    end
  end

  describe "a direct request and its undo" do
    test "cria direto creates at once, and desfaz closes it once", %{repo: repo} do
      {:ok, calls} = Elixir.Agent.start_link(fn -> [] end)

      Req.Test.stub(@stub, fn conn ->
        Elixir.Agent.update(calls, &[{conn.method, conn.request_path} | &1])

        Req.Test.json(conn, %{
          "number" => 42,
          "html_url" => "https://github.com/sallaumen/arena-rogue/issues/42"
        })
      end)

      script(fn %{name: :voice_agent} ->
        agent_answer("create_task", %{
          "request" => "corrigir o botão de salvar",
          "title" => "Corrigir o botão de salvar",
          "details" => ["o botão salva"],
          "question" => "Qual botão?",
          "direct" => true
        })
      end)

      created = turn("cria direto: corrigir o botão de salvar", repo)

      assert created.reply == "Criei a tarefa 42 no arena-rogue. Se não era isso, diga desfaz."
      refute created.listen
      assert Conversation.pending_proposal() == nil
      assert %Task{state: "queued"} = Repo.get_by!(Task, repository_id: repo.id, number: 42)

      script(fn _ -> flunk("desfaz is local") end)
      assert %{reply: "Desfeito. Fechei a tarefa 42.", action: "undo"} = turn("desfaz", repo)
      assert %Task{stopped: true} = Repo.get_by!(Task, repository_id: repo.id, number: 42)
      assert {"PATCH", "/repos/sallaumen/arena-rogue/issues/42"} in Elixir.Agent.get(calls, & &1)

      assert %{reply: "Não tenho nada para desfazer dos últimos dez minutos."} =
               turn("desfaz", repo)
    end

    test "desfaz never closes a task the voice did not create", %{repo: repo} do
      task!(repo, %{number: 8, title: "De outra pessoa"})
      script(fn _ -> flunk("desfaz is local") end)

      assert %{reply: "Não tenho nada para desfazer dos últimos dez minutos."} =
               turn("desfaz", repo)

      assert %Task{stopped: false} = Repo.get_by!(Task, repository_id: repo.id, number: 8)
    end
  end

  describe "the catalog" do
    test "every lookup in the catalog is one the model's schema allows" do
      {:ok, spec} = Registry.fetch(:voice_agent)
      allowed = spec.json_schema["properties"]["lookup"]["enum"] -- [""]
      assert Enum.sort(Commands.lookups()) == Enum.sort(allowed)
    end

    test "the explain call is registered with a rehearsal fixture" do
      assert {:ok, %{json_schema: %{"required" => ["reply"]}}} = Registry.fetch(:voice_explain)
    end

    test "every item names what it does and how it runs" do
      for item <- Commands.items() do
        assert item.say != "" and item.does != ""
        assert item.mode in [:local, :read, :confirm, :direct]
        # A ready-to-send example never carries a task number to fill in.
        if item.try, do: refute(item.say =~ ~r/\d/)
      end
    end

    test "search words drop filler and fold accents" do
      assert Lookup.words("Acha a tarefa sobre o Botão de áudio") == ["botao", "audio"]
      assert Lookup.words(nil) == []
    end
  end

  defp with_tickets(tickets) do
    path =
      Path.join(System.tmp_dir!(), "voice-commands-#{System.unique_integer([:positive])}.sqlite")

    {:ok, conn} = Exqlite.Sqlite3.open(path)
    :ok = Exqlite.Sqlite3.execute(conn, "create table ticket (value text)")

    for ticket <- tickets do
      {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "insert into ticket (value) values (?1)")
      :ok = Exqlite.Sqlite3.bind(stmt, [Jason.encode!(ticket)])
      :done = Exqlite.Sqlite3.step(conn, stmt)
      Exqlite.Sqlite3.release(conn, stmt)
    end

    Exqlite.Sqlite3.close(conn)
    Application.put_env(:agent_board, :state_db, path)
    on_exit(fn -> for s <- ["", "-wal", "-shm"], do: File.rm(path <> s) end)
  end
end
