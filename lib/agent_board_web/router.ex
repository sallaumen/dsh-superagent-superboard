defmodule AgentBoardWeb.Router do
  use AgentBoardWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AgentBoardWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AgentBoardWeb do
    pipe_through :browser

    live "/", BoardLive
  end

  scope "/api", AgentBoardWeb do
    pipe_through :api

    get "/board", BoardController, :board
    get "/repos", BoardController, :repos
    post "/repos", BoardController, :add_repo
    post "/tasks", BoardController, :create_task
    patch "/tasks/:id", BoardController, :act
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
