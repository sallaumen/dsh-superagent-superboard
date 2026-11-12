defmodule AgentBoardWeb.SuperagentPanelController do
  @moduledoc """
  Sends this browser to an agent's dsh panel, signed in
  (`AgentBoard.Superagents.PanelLink`).

  The address carries dsh's launch token, so the redirect is given only to a
  browser on the machine the board runs on, that opened the board by a local
  name: behind a proxy every request looks local, and the name is what tells
  them apart. It is a POST with the session's CSRF token, so another site
  cannot make this browser sign in. Whatever goes wrong comes back to
  Projects as a sentence; the address is never in a page or a log.
  """
  use AgentBoardWeb, :controller
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Superagents
  alias AgentBoard.Superagents.{PanelLink, Superagent}

  @loopback [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}, {0, 0, 0, 0, 0, 65_535, 32_512, 1}]

  def open(conn, %{"id" => id}) do
    with true <- local?(conn.remote_ip, conn.host) || :remote,
         %Superagent{} = superagent <- Superagents.get(id),
         {:ok, address} <- PanelLink.url(superagent) do
      conn |> put_status(:see_other) |> redirect(external: address)
    else
      problem ->
        conn
        |> put_flash(:error, sentence(problem))
        |> redirect(to: ~p"/?panel=settings&section=projects")
    end
  end

  @doc false
  # The endpoint also serves its configured public host (`refuse_foreign_host`):
  # that name is not this machine's browser.
  def local?(ip, host) do
    ip in @loopback and
      (host in ~w(localhost 127.0.0.1 [::1]) or String.ends_with?(host, ".localhost"))
  end

  defp sentence(:remote),
    do:
      gettext(
        "The dsh panel opens only in a browser on the machine where the agent runs, with the board opened as localhost."
      )

  defp sentence(nil), do: gettext("That project no longer has an agent.")

  defp sentence({:error, {:unreadable, _reason}}),
    do:
      gettext(
        "The board may not read the agent's log on this machine, so it cannot open the panel signed in. The command in the project's controls does it from a terminal."
      )

  defp sentence({:error, :foreign}),
    do:
      gettext(
        "The address in the agent's log is not this agent's panel on this machine. Nothing was opened."
      )

  defp sentence({:error, _no_log_or_address}),
    do:
      gettext(
        "The agent's log has no panel address yet. Start the agent from the board and try again."
      )
end
