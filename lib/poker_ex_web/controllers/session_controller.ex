defmodule PokerExWeb.SessionController do
  use PokerExWeb, :controller

  action_fallback(PokerExWeb.FallbackController)

  def new(conn, _) do
    render(conn, "new.html")
  end

  def create(conn, %{"session" => %{"name" => player, "password" => pass}}) do
    case PokerExWeb.Auth.login_by_username_and_pass(conn, player, pass, repo: Repo) do
      {:ok, conn} ->
        conn
        |> put_flash(:info, "Welcome back!")
        |> redirect(
          to: Routes.player_path(conn, :show, Repo.get_by(PokerEx.Player, name: player).id)
        )

      {:error, _reason, conn} ->
        conn
        |> put_flash(:error, "Invalid username/password combination")
        |> render("new.html")
    end
  end

  # API sign-ins
  def create(conn, %{"player" => %{"username" => username, "password" => pass}}) do
    api_sign_in(conn, username, pass)
  end

  def delete(conn, _) do
    conn
    |> PokerExWeb.Auth.logout()
    |> redirect(to: Routes.page_path(conn, :index))
  end
end
