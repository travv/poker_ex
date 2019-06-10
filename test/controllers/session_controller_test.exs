defmodule PokerExWeb.SessionControllerTest do
  use PokerExWeb.ConnCase, async: false

  setup do
    player = insert_user(username: "Testuser")
    conn = assign(build_conn(), :current_player, player)
    %{conn: conn, player: player}
  end

  test "renders SessionView's login.json with a 200 response when credentials are correct",
       context do
    conn =
      post(
        context.conn,
        session_path(context.conn, :create, %{
          "player" => %{
            "username" => context.player.name,
            "password" => "secretpassword"
          }
        })
      )

    assert json_response(conn, 200)
    assert String.contains?(conn.resp_body, "{\"player\":{")
  end

  test "renders error status when a user tries to log in with bad credentials", context do
    conn =
      post(
        context.conn,
        session_path(context.conn, :create, %{
          "player" => %{
            "username" => context.player.name,
            "password" => "not my password"
          }
        })
      )

    assert conn.status == 401
    assert conn.resp_body =~ ~r({\"message\":\"Unauthorized\"})
  end
end
