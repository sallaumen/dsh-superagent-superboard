defmodule AgentBoardWeb.RuntimeSyncController do
  @moduledoc "One local, CSRF-protected maintenance click for the displayed registered projects."
  use AgentBoardWeb, :controller
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.{Actions, Superagents}
  alias AgentBoard.Superagents.RuntimeSync
  alias AgentBoardWeb.{Locale, SuperagentPanelController}

  def create(conn, params) do
    if SuperagentPanelController.local?(conn.remote_ip, conn.host) do
      targets = RuntimeSync.targets(Superagents.list())

      case Actions.run(:sync_agent_runtimes, %{targets: targets}, Actions.owner(:ui),
             confirm: if(is_binary(params["confirm"]), do: params["confirm"]),
             language: Locale.language()
           ) do
        :ok ->
          back(conn, :info, gettext("Synchronization started."))

        {:error, :in_progress} ->
          back(conn, :info, gettext("Synchronization is already running."))

        _ ->
          back(conn, :error, gettext("Review the current project list and try again."))
      end
    else
      conn
      |> put_status(:forbidden)
      |> text(gettext("Open Settings on localhost to manage this machine’s agents."))
    end
  end

  defp back(conn, kind, message),
    do:
      conn
      |> put_flash(kind, message)
      |> put_status(:see_other)
      |> redirect(to: ~p"/?panel=settings&section=projects")
end
