defmodule PokerExWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :poker_ex

  socket("/socket", PokerExWeb.UserSocket,
    websocket: [
      timeout: 45_000,
      check_origin: [
        "http://localhost:8080",
        "http://localhost:8081",
        "http://0.0.0.0:8081",
        "http://10.20.30.194",
        "https://ancient-forest-15148.herokuapp.com/",
        "https://poker-ex.herokuapp.com/"
      ]
    ]
  )

  # Enable concurrent testing
  if Application.get_env(:poker_ex, :sql_sandbox) do
    plug(Phoenix.Ecto.SQL.Sandbox)
  end

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug(Plug.Static,
    at: "/",
    from: :poker_ex,
    gzip: false,
    only: ~w(css fonts images js favicon.ico robots.txt)
  )

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Logger)

  plug(CORSPlug,
    origin: [
      "http://localhost:8081",
      "http://0.0.0.0:8081",
      "http://10.20.30.194",
      "http://phoenix-experiment-zkayser.c9users.io:8081",
      "https://poker-ex.herokuapp.com"
    ]
  )

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Poison
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug(Plug.Session,
    store: :cookie,
    key: "_poker_ex_key",
    signing_salt: "UaO/i7Og"
  )

  plug(PokerExWeb.Router)
end
