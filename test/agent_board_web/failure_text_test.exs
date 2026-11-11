defmodule AgentBoardWeb.FailureTextTest do
  use ExUnit.Case, async: false

  alias AgentBoard.GitHub.{HTTPError, RateLimited}
  alias AgentBoardWeb.FailureText

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "pt_BR")
    on_exit(fn -> Gettext.put_locale(AgentBoardWeb.Gettext, "en") end)
  end

  test "a reason the board knows says what happened" do
    assert FailureText.text(:not_configured) =~ "chave"
    assert FailureText.text(:auth_expired) =~ "recusou"
    assert FailureText.text(:usage_limit) =~ "limite"
    assert FailureText.text(:budget_exhausted) =~ "orçamento"
    assert FailureText.text(:timeout) =~ "não respondeu a tempo"
    assert FailureText.text(:unreachable) =~ "não respondeu"
    assert FailureText.text({:http, 503}) =~ "503"
    assert FailureText.text(%RateLimited{retry_after: 120}) =~ "2 min"
    assert FailureText.text(%Req.TransportError{reason: :closed}) =~ "conexão"
    assert FailureText.text(%Req.TransportError{reason: :nxdomain}) =~ "rede"
  end

  test "preparing a project says what the profile or the form lacks" do
    assert FailureText.text({:profile_port_missing, "superagent"}) =~ "superagent"
    assert FailureText.text({:profile_port_missing, "superagent"}) =~ "porta"
    assert FailureText.text(:profile_missing) =~ "nesta máquina"
    assert FailureText.text(:source_required) =~ "Escolha o perfil"

    first..last//_ = AgentBoard.Orchestrator.worker_range()
    assert FailureText.text(:invalid_workers) =~ "de #{first} a #{last}"

    changeset = Ecto.Changeset.change(%AgentBoard.Board.Repository{}) |> Map.put(:valid?, false)
    assert FailureText.text({:error, changeset}) =~ "formulário"
    refute FailureText.text(changeset) =~ "%"
  end

  test "a GitHub answer is said without its body" do
    text = FailureText.text(%HTTPError{status: 404, body: %{"message" => "Not Found"}})

    assert text =~ "404"
    refute text =~ "%{"
  end

  test "a refused token is named, not just numbered" do
    for status <- [401, 403] do
      text = FailureText.text(%HTTPError{status: status, body: %{}})

      assert text =~ "recusou o token"
      assert text =~ "#{status}"
    end
  end

  test "nothing internal reaches the screen" do
    text = FailureText.text({:error, %{some: :internal, term: [1, 2, 3]}})

    refute text =~ "%{"
    refute text =~ "internal"
    assert text =~ "registro"
  end
end
