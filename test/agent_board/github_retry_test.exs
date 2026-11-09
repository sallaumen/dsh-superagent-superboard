defmodule AgentBoard.GitHubRetryTest do
  @moduledoc """
  What the GitHub client tries again by itself: a read, or a write that cannot
  have reached GitHub. A write that may have landed is left to the person.
  """
  use ExUnit.Case, async: false

  alias AgentBoard.GitHub

  @stub AgentBoard.GitHubRetryTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})

    {:ok, calls} = Agent.start_link(fn -> 0 end)

    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    %{calls: calls}
  end

  defp client do
    Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub})
    |> Req.merge(GitHub.retry_options())
  end

  # Answers `first` once for each of `fails` calls, then 200.
  defp stub(calls, fails, first) do
    Req.Test.stub(@stub, fn conn ->
      count = Agent.get_and_update(calls, &{&1 + 1, &1 + 1})

      if count <= fails do
        first.(conn)
      else
        Req.Test.json(conn, %{"number" => 1, "html_url" => "https://github.com/a/b/issues/1"})
      end
    end)
  end

  defp status(code), do: &Plug.Conn.send_resp(&1, code, "boom")
  defp transport(reason), do: &Req.Test.transport_error(&1, reason)

  describe "a read" do
    for code <- [500, 502, 503, 504] do
      test "comes back from a #{code}", %{calls: calls} do
        stub(calls, 1, status(unquote(code)))

        assert %{"number" => 1} = GitHub.reviews(client(), "a", "b", 1)

        assert Agent.get(calls, & &1) == 2
      end
    end

    for reason <- [:closed, :timeout, :econnrefused, :nxdomain] do
      test "comes back from a dropped connection (#{reason})", %{calls: calls} do
        stub(calls, 2, transport(unquote(reason)))

        assert %{"number" => 1} = GitHub.reviews(client(), "a", "b", 1)
        assert Agent.get(calls, & &1) == 3
      end
    end

    test "gives up after two more tries and says why", %{calls: calls} do
      stub(calls, 99, status(502))

      assert_raise RuntimeError, ~r/GitHub HTTP 502/, fn ->
        GitHub.reviews(client(), "a", "b", 1)
      end

      assert Agent.get(calls, & &1) == 3
    end

    for code <- [401, 404, 422] do
      test "does not repeat a #{code}", %{calls: calls} do
        stub(calls, 99, status(unquote(code)))

        assert_raise RuntimeError, fn -> GitHub.reviews(client(), "a", "b", 1) end
        assert Agent.get(calls, & &1) == 1
      end
    end
  end

  describe "a write" do
    test "that may have landed is not repeated", %{calls: calls} do
      for fail <- [status(502), transport(:closed), transport(:timeout)] do
        Agent.update(calls, fn _ -> 0 end)
        stub(calls, 99, fail)

        assert_raise_any(fn -> GitHub.create_issue(client(), "a", "b", "t", "b", []) end)
        assert Agent.get(calls, & &1) == 1
      end
    end

    test "that never reached GitHub is tried again", %{calls: calls} do
      stub(calls, 1, transport(:econnrefused))

      assert %{"number" => 1} = GitHub.create_issue(client(), "a", "b", "t", "b", [])
      assert Agent.get(calls, & &1) == 2
    end

    test "that closes an issue can be repeated", %{calls: calls} do
      stub(calls, 1, status(502))

      assert %{"number" => 1} = GitHub.close_issue(client(), "a", "b", 1)
      assert Agent.get(calls, & &1) == 2
    end
  end

  describe "the rate limit" do
    test "a 429 is not repeated, and carries the wait as a number", %{calls: calls} do
      Req.Test.stub(@stub, fn conn ->
        Agent.update(calls, &(&1 + 1))

        conn
        |> Plug.Conn.put_resp_header("retry-after", "17")
        |> Plug.Conn.send_resp(429, "slow down")
      end)

      error =
        assert_raise GitHub.RateLimited, fn -> GitHub.reviews(client(), "a", "b", 1) end

      assert error.retry_after == 17
      assert Agent.get(calls, & &1) == 1
    end

    test "a spent quota waits until GitHub's reset" do
      reset = System.system_time(:second) + 600

      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-ratelimit-remaining", "0")
        |> Plug.Conn.put_resp_header("x-ratelimit-reset", to_string(reset))
        |> Plug.Conn.send_resp(403, "API rate limit exceeded")
      end)

      error =
        assert_raise GitHub.RateLimited, fn -> GitHub.reviews(client(), "a", "b", 1) end

      assert error.retry_after in 595..600
    end

    test "a 403 with no sign of a limit is a refusal, not a rate limit" do
      Req.Test.stub(@stub, fn conn ->
        Req.Test.json(Plug.Conn.put_status(conn, 403), %{
          "message" => "Resource not accessible by personal access token"
        })
      end)

      assert_raise RuntimeError, ~r/GitHub HTTP 403/, fn ->
        GitHub.reviews(client(), "a", "b", 1)
      end
    end
  end

  defp assert_raise_any(fun) do
    fun.()
    flunk("expected a raise")
  rescue
    ExUnit.AssertionError -> flunk("expected a raise")
    _exception -> :ok
  end
end
