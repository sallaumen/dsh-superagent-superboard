defmodule AgentBoard.AutoRetryTest do
  @moduledoc """
  The board retries a transient failure by itself: once per Assignment, at
  most three times per streak, only when the orchestrator answers, and
  every request is an event. The orchestrator is a Req.Test stub.
  """
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{AgentState, AutoRetry, Orchestrator, Repo}
  alias AgentBoard.AutoRetry.Attempt
  alias AgentBoard.Board.{Event, Repository}

  @stub AgentBoard.AutoRetryTest.Stub
  @failed_at ~U[2026-11-07 15:41:51Z]
  @model "LlmError: DeepSeek Messages transport failed"
  @prepare "Error: The prepare command failed: fatal: unable to access " <>
             "'https://github.com/sallaumen/arena-rogue.git/': Could not resolve host: github.com"

  setup do
    previous_api = Application.get_env(:agent_board, :orchestrator_api)
    Application.put_env(:agent_board, :orchestrator_api, "http://127.0.0.1:1/orchestrator/api")
    client = Req.merge(Orchestrator.build(), plug: {Req.Test, @stub})

    on_exit(fn ->
      if is_nil(previous_api),
        do: Application.delete_env(:agent_board, :orchestrator_api),
        else: Application.put_env(:agent_board, :orchestrator_api, previous_api)
    end)

    # An id outside the sandbox range keeps the broadcast topic private.
    repo =
      %Repository{}
      |> Repository.changeset(%{owner: "sallaumen", name: "arena-rogue"})
      |> Ecto.Changeset.put_change(:id, 2_000_000 + System.unique_integer([:positive]))
      |> Repo.insert!()

    %{client: client, repo: repo}
  end

  # The orchestrator: `GET /state` answers `state`, `POST .../retry` answers
  # `retry`; every request is reported to the test.
  defp orchestrator(opts \\ []) do
    test = self()
    state = Keyword.get(opts, :state, :up)
    retry = Keyword.get(opts, :retry, :ok)

    Req.Test.stub(@stub, fn conn ->
      send(test, {:request, conn.method, conn.request_path})

      case {conn.method, state, retry} do
        {"GET", :up, _} ->
          Req.Test.json(conn, %{"load" => %{"running" => 0, "queued" => 0, "maxWorkers" => 3}})

        {"GET", :down, _} ->
          Req.Test.transport_error(conn, :econnrefused)

        {"POST", _, :ok} ->
          Req.Test.json(conn, %{"retried" => true})

        {"POST", _, :refused} ->
          conn
          |> Plug.Conn.put_status(400)
          |> Req.Test.json(%{"error" => "Only an open ticket…", "code" => "notRetryable"})

        {"POST", _, :unreachable} ->
          Req.Test.transport_error(conn, :econnrefused)
      end
    end)
  end

  # A ticket as the runner stores it, normalized the way the board reads it.
  # `history` is the Assignments before the latest, each `{report, ended}`.
  defp ticket(summary, opts \\ []) do
    history =
      for {{report, ended}, i} <- Enum.with_index(Keyword.get(opts, :history, [])) do
        %{
          "id" => "a#{i}",
          "state" => "ended",
          "report" =>
            report && %{"state" => report, "summary" => "earlier", "at" => "2026-11-07T14:00:00Z"},
          "endedReason" => ended
        }
      end

    latest = %{
      "id" => Keyword.get(opts, :assignment, "latest"),
      "state" => "running",
      "report" => %{
        "state" => "failed",
        "summary" => summary,
        "at" => DateTime.to_iso8601(@failed_at)
      },
      "idleAt" => DateTime.to_iso8601(@failed_at)
    }

    AgentState.normalize(%{
      "id" => Keyword.get(opts, :id, "t1"),
      "title" => "Revisar textos",
      "mandate" => %{"basis" => %{"scope" => %{"number" => 53}}},
      "channels" => [
        %{
          "address" => %{
            "number" => 53,
            "url" => "https://github.com/sallaumen/arena-rogue/issues/53"
          }
        }
      ],
      "execution" => %{
        "directory" => Keyword.get(opts, :directory, "/nonexistent/agent-retry-test")
      },
      "assignments" => history ++ [latest]
    })
  end

  defp at(seconds), do: DateTime.add(@failed_at, seconds, :second)

  defp tick(client, tickets, seconds),
    do: AutoRetry.tick(client: client, tickets: tickets, now: at(seconds))

  defp posts do
    receive do
      {:request, "POST", path} -> [path | posts()]
      {:request, _method, _path} -> posts()
    after
      0 -> []
    end
  end

  defp requests do
    receive do
      {:request, method, path} -> [{method, path} | requests()]
    after
      0 -> []
    end
  end

  describe "plan/2" do
    test "a transient failure is scheduled one minute after it, attempt 1 of 3" do
      assert %{state: :scheduled, attempt: 1, max: 3, retries: 0, due_at: due} =
               AutoRetry.plan(ticket(@model))

      assert due == at(60)
    end

    test "the second and third retries wait 5 and 15 minutes" do
      assert %{attempt: 2, due_at: due} =
               AutoRetry.plan(ticket(@model, history: [{"failed", "retried"}]))

      assert due == at(300)

      assert %{attempt: 3, due_at: due} =
               AutoRetry.plan(
                 ticket(@model, history: [{"failed", "retried"}, {"failed", "retried"}])
               )

      assert due == at(900)
    end

    test "three retries in the streak exhaust it" do
      history = List.duplicate({"failed", "retried"}, 3)

      assert %{state: :exhausted, retries: 3, due_at: nil} =
               AutoRetry.plan(ticket(@model, history: history))
    end

    test "a report other than a failure ends the streak; a restart without one does not" do
      history = [
        {"failed", "retried"},
        {"waiting", "retried"},
        {"failed", "retried"},
        {nil, "hostRestarted"}
      ]

      assert %{state: :scheduled, retries: 1} = AutoRetry.plan(ticket(@model, history: history))
    end

    test "a failure that is not transient needs a person" do
      assert %{state: :needs_person, due_at: nil} = AutoRetry.plan(ticket("Tests failed: 3"))
    end

    test "a prepare that left files behind needs a person, an empty one is retried" do
      assert %{state: :needs_person, leftover: true} =
               AutoRetry.plan(ticket(@prepare), leftover?: fn _dir -> true end)

      assert %{state: :scheduled, leftover: false} =
               AutoRetry.plan(ticket(@prepare), leftover?: fn _dir -> false end)
    end

    test "no plan for a ticket whose latest Assignment did not fail, or that ended" do
      waiting =
        AgentState.normalize(%{
          "id" => "t2",
          "assignments" => [%{"id" => "x", "report" => %{"state" => "waiting"}}]
        })

      assert AutoRetry.plan(waiting) == nil
      assert AutoRetry.plan(Map.put(ticket(@model), "ended_outcome", "dropped")) == nil
      assert AutoRetry.plan(Map.put(ticket(@model), "stopped", true)) == nil
    end
  end

  describe "tick/1" do
    test "a transient failure is retried once its delay passed, and recorded", %{
      client: client,
      repo: repo
    } do
      orchestrator()

      assert tick(client, [ticket(@model)], 30) == []
      assert requests() == [], "nothing due: the orchestrator is not even asked"

      assert tick(client, [ticket(@model)], 61) == [{"t1", "retried"}]
      assert posts() == ["/orchestrator/api/tickets/t1/retry"]

      assert [
               %Attempt{
                 assignment_id: "latest",
                 attempt: 1,
                 outcome: "retried",
                 cause: "model_transport"
               }
             ] =
               Repo.all(Attempt)

      assert [%Event{kind: "agent_retry", subject: subject, payload: payload}] =
               Repo.all(from e in Event, where: e.repository_id == ^repo.id)

      assert subject ==
               "Nova tentativa automática 1 de 3 em #53: falha de rede ao chamar o modelo"

      assert %{"ticket_id" => "t1", "assignment_id" => "latest", "outcome" => "retried"} = payload
    end

    test "the same Assignment is never retried twice", %{client: client} do
      orchestrator()

      assert [{"t1", "retried"}] = tick(client, [ticket(@model)], 61)
      # The runner state has not moved yet: the same failure is read again.
      assert tick(client, [ticket(@model)], 120) == []
      assert tick(client, [ticket(@model)], 3_600) == []
      assert length(posts()) == 1
      assert Repo.aggregate(Attempt, :count) == 1
    end

    test "a failure that needs a person is never retried", %{client: client} do
      orchestrator()
      assert tick(client, [ticket("Tests failed: 3 failures")], 3_600) == []
      assert requests() == []
    end

    test "an exhausted streak is not retried", %{client: client} do
      orchestrator()
      history = List.duplicate({"failed", "retried"}, 3)
      assert tick(client, [ticket(@model, history: history)], 3_600) == []
      assert requests() == []
    end

    test "nothing is sent while the orchestrator does not answer", %{client: client} do
      orchestrator(state: :down)
      assert tick(client, [ticket(@model)], 61) == []
      assert requests() == [{"GET", "/orchestrator/api/state"}]
      assert Repo.aggregate(Attempt, :count) == 0

      orchestrator()
      assert tick(client, [ticket(@model)], 90) == [{"t1", "retried"}]
    end

    test "an unanswered retry is sent again after the cool-down, not before", %{client: client} do
      orchestrator(retry: :unreachable)
      assert tick(client, [ticket(@model)], 61) == [{"t1", "unreachable"}]

      orchestrator()
      assert tick(client, [ticket(@model)], 90) == []
      assert tick(client, [ticket(@model)], 200) == [{"t1", "retried"}]
      assert [%Attempt{outcome: "retried"}] = Repo.all(Attempt)
    end

    test "a refusal is final for that Assignment and shows as an error event", %{
      client: client,
      repo: repo
    } do
      orchestrator(retry: :refused)
      assert tick(client, [ticket(@model)], 61) == [{"t1", "refused"}]
      assert tick(client, [ticket(@model)], 3_600) == []

      assert [%Attempt{outcome: "refused", detail: "notRetryable"}] = Repo.all(Attempt)

      assert [%Event{kind: "agent_retry_error", subject: subject}] =
               Repo.all(from e in Event, where: e.repository_id == ^repo.id)

      assert subject =~ "não foi aceita (o agente recusou: notRetryable)"
    end

    test "a new failure on the next Assignment is attempt 2", %{client: client} do
      orchestrator()
      assert [{"t1", "retried"}] = tick(client, [ticket(@model)], 61)

      second = ticket(@model, assignment: "second", history: [{"failed", "retried"}])
      assert tick(client, [second], 120) == [], "attempt 2 waits five minutes"
      assert tick(client, [second], 301) == [{"t1", "retried"}]

      assert [%Attempt{attempt: 1}, %Attempt{attempt: 2, assignment_id: "second"}] =
               Repo.all(from a in Attempt, order_by: a.id)
    end

    test "the switch turns the writes off", %{client: client} do
      orchestrator()
      Application.put_env(:agent_board, :auto_retry, false)
      on_exit(fn -> Application.delete_env(:agent_board, :auto_retry) end)

      assert tick(client, [ticket(@model)], 3_600) == []
      assert requests() == []
    end
  end
end
