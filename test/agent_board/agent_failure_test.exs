defmodule AgentBoard.AgentFailureTest do
  @moduledoc "A failed report is transient only when its text says the network or the provider failed."
  use ExUnit.Case, async: true

  alias AgentBoard.AgentFailure

  # The two failures the reboot of 2026-11-07 left on the board, verbatim.
  @model "LlmError: DeepSeek Messages transport failed"
  @prepare "Error: The prepare command failed: fatal: unable to access " <>
             "'https://github.com/sallaumen/arena-rogue.git/': Could not resolve host: github.com"

  test "the stored sentence is the screen's English one, whoever reads" do
    failures =
      for transient <- [true, false],
          stage <- [:model, :prepare, :other],
          cause <- [:rate_limit, :provider_unavailable, :dns, :hung, :unknown] do
        %{transient: transient, stage: stage, cause: cause, summary: ""}
      end

    Gettext.put_locale(AgentBoardWeb.Gettext, "en")

    for failure <- failures,
        do: assert(AgentFailure.headline(failure) == AgentFailure.describe(failure))

    Gettext.put_locale(AgentBoardWeb.Gettext, "pt_BR")

    for failure <- failures,
        do: refute(AgentFailure.headline(failure) == AgentFailure.describe(failure))

    assert AgentFailure.headline(AgentFailure.classify(@model)) ==
             "Falha de rede ao chamar o modelo"

    assert AgentFailure.describe(AgentFailure.classify(@model)) ==
             "Network failure calling the model"

    # asking for the stored sentence does not change the reader's language
    assert Gettext.get_locale(AgentBoardWeb.Gettext) == "pt_BR"
  end

  test "the model's transport failing is transient, at the model" do
    assert %{transient: true, cause: :model_transport, stage: :model} =
             AgentFailure.classify(@model)

    assert AgentFailure.describe(AgentFailure.classify(@model)) ==
             "Network failure calling the model"
  end

  test "a host that did not resolve during the prepare is transient, at the prepare" do
    failure = AgentFailure.classify(@prepare)
    assert %{transient: true, cause: :dns, stage: :prepare} = failure

    assert AgentFailure.describe(failure) ==
             "No network preparing the worktree: GitHub did not resolve"
  end

  test "refused, reset, timed out, rate limited and 5xx are transient" do
    for {text, cause} <- [
          {"Error: connect ECONNREFUSED 127.0.0.1:443", :connection},
          {"fetch failed: socket hang up", :connection},
          {"LlmError: request timed out", :timeout},
          {"LlmError: 429 Too Many Requests", :rate_limit},
          {"LlmError: 503 Service Unavailable", :provider_unavailable}
        ] do
      assert %{transient: true, cause: ^cause} = AgentFailure.classify(text), text
    end
  end

  test "an unknown text, a refused credential or a hung prepare needs a person" do
    for text <- [
          "Tests failed: 3 failures in board_test.exs",
          "LlmError: 401 Unauthorized",
          "LlmError: insufficient balance",
          "Error: The prepare command failed: The operation was aborted due to timeout",
          "",
          nil
        ] do
      assert %{transient: false} = AgentFailure.classify(text), inspect(text)
    end

    assert AgentFailure.describe(
             AgentFailure.classify(
               "Error: The prepare command failed: The operation was aborted due to timeout"
             )
           ) == "Preparing the worktree timed out"
  end
end
