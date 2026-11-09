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
  end

  # Audio responses are not JSON: the browser fetches the speech endpoint
  # with `Accept: audio/mpeg` (which Phoenix maps to the "mp3" format), and
  # the error bodies are still JSON.
  pipeline :voice do
    plug :accepts, ["json", "mp3"]
  end

  scope "/", AgentBoardWeb do
    pipe_through :browser

    post "/language", LocaleController, :update
    get "/attachments/:repo_id/:hash/:name", AttachmentController, :show

    live_session :board, on_mount: {AgentBoardWeb.Locale, :default} do
      live "/", BoardLive
    end
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
end
