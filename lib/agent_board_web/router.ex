defmodule AgentBoardWeb.Router do
  use AgentBoardWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug AgentBoardWeb.Locale
    plug :fetch_live_flash
    plug :put_root_layout, html: {AgentBoardWeb.Layouts, :root}
    plug :protect_from_forgery
    # sobelow flagged the missing policy. The inline script is the theme
    # bootstrap in the root layout, so script-src needs 'unsafe-inline'.
    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: blob:; media-src 'self' blob:; connect-src 'self' ws: wss:; frame-ancestors 'self'"
    }
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :refuse_cross_site
  end

  # Audio responses are not JSON: the browser fetches the speech endpoint
  # with `Accept: audio/mpeg` (which Phoenix maps to the "mp3" format), and
  # the error bodies are still JSON.
  pipeline :voice do
    plug :accepts, ["json", "mp3"]
    plug :refuse_cross_site
  end

  scope "/", AgentBoardWeb do
    pipe_through :browser

    post "/superagents/synchronize", RuntimeSyncController, :create
    post "/language", LocaleController, :update
    post "/superagents/:id/panel", SuperagentPanelController, :open

    live_session :board, on_mount: {AgentBoardWeb.Locale, :default} do
      live "/", BoardLive
    end
  end

  # Each image is a GitHub call on the board's token: another site's <img>
  # tags would spend the hourly quota. The board's own <img> is same-origin.
  scope "/", AgentBoardWeb do
    pipe_through [:browser, :refuse_cross_site]

    get "/attachments/:repo_id/:hash/:name", AttachmentController, :show
    get "/private/:repo_id/:dir/*path", PrivateFileController, :show
  end

  scope "/api", AgentBoardWeb do
    pipe_through :api

    get "/board", BoardController, :board
    get "/repos", BoardController, :repos
    post "/repos", BoardController, :add_repo
    post "/tasks", BoardController, :create_task
    patch "/tasks/:id", BoardController, :act

    get "/voice/status", VoiceController, :status
    get "/voice/voices", VoiceController, :voices
    put "/voice/settings", VoiceController, :update
    post "/voice/transcribe", VoiceController, :transcribe
  end

  scope "/api", AgentBoardWeb do
    pipe_through :voice

    get "/voice/speech", VoiceController, :speech
    get "/voice/stream", VoiceController, :stream
    post "/voice/speech", VoiceController, :speech_post
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:agent_board, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AgentBoardWeb.Telemetry
    end
  end

  # The API has no login and listens on 127.0.0.1 only, but a page on another
  # site can still reach localhost with a form or an <audio src>. The browser
  # says where a request comes from; the board's page is same-origin and a
  # script sends no header.
  defp refuse_cross_site(conn, _opts) do
    case get_req_header(conn, "sec-fetch-site") do
      [site] when site in ["cross-site", "same-site"] ->
        conn
        |> put_status(:forbidden)
        |> Phoenix.Controller.json(%{error: "cross_site_request"})
        |> halt()

      _ ->
        conn
    end
  end
end
