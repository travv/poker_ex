defmodule PokerExWeb.Live.GameTest do
  import Phoenix.LiveViewTest
  use PokerExWeb.ConnCase

  describe "joining a game" do
    test "entering a name in the name-input field populates the player's name", %{conn: conn} do
      {:ok, view, _html} = live(conn, "games/game_1")
      name = "some player name"

      assert render_change(view, :change_name, %{"name" => name}) =~ name
    end

    test "entering a name in the name-input field enables the join game button", %{conn: conn} do
      {:ok, view, _html} = live(conn, "games/game_1")
      name = "some player name"

      html = render_change(view, :change_name, %{"name" => name})
      refute html =~ "disabled"
    end

    test "clicking the join button while disabled does nothing", %{conn: conn} do
      {:ok, view, html} = live(conn, "games/game_1")

      update = render_click(view, :attempt_join)
      assert html =~ update
    end

    test "clicking the join button while enabled removes the join form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "games/game_1")

      render_change(view, :change_name, %{"name" => "a unique user name"})
      refute render_click(view, :attempt_join) =~ "data-testid=\"join-component\""
    end
  end
end
