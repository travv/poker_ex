defmodule PokerExWeb.AuthController do
  @moduledoc """
  Gives users the option to sign in via Facebook
  and other strategies
  """

  use PokerExWeb, :controller
  alias Ueberauth.Strategy.Helpers
  alias PokerExWeb.Auth
  alias PokerEx.MapUtils
  require Logger
  plug(Ueberauth)

  @unauthorized_message "Authorization failed"

  def request(conn, _params) do
    render(conn, "request.html", callback_url: Helpers.callback_url(conn))
  end

  def callback(%{assigns: %{ueberauth_failure: fail}} = conn, params) do
    Logger.warn(
      "Auth callback received with conn:\n#{inspect(fail)}\nand params: #{inspect(params)}"
    )

    redirect(conn, to: "/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_info = auth.extra.raw_info.user

    case Repo.get_by(PokerEx.Player, email: user_info["email"]) do
      %PokerEx.Player{} = player ->
        login_and_redirect(%{conn: conn, message: "Welcome back, #{player.name}", player: player})

      _ ->
        maybe_insert_player(conn, user_info)
    end
  end

  def oauth_handler(conn, %{"name" => name, "facebook_id" => id} = provider_data) do
    conn =
      case PokerEx.Player.fb_login_or_create(MapUtils.to_atom_keys(provider_data)) do
        %PokerEx.Player{} = player ->
          api_sign_in(conn, player.name, %{facebook_id: id}, &Auth.oauth_login/4)

        :error ->
          conn |> put_status(:unauthorized) |> json(%{message: @unauthorized_message})

        :unauthorized ->
          conn |> put_status(:unauthorized) |> json(%{message: @unauthorized_message})
      end

    conn
  end

  def oauth_handler(conn, %{"email" => _email, "google_token_id" => token} = provider_data) do
    Logger.debug("[OAUTH_HANDLER] Called with provider_data: #{inspect(provider_data)}")
    # HTTPotion.get(@google_certs_endpoint)
    # Call and cache Google's certs endpoint: https://www.googleapis.com/oauth2/v3/certs
    # Gives a list of keys. Use the one with the matching kid (key ID) from the header.
    # json = GoogleApi.Certs.get()
    ## ==>  Get header kid
    # kid = Guardian.peek_header(token)["kid"]
    # key_json = Enum.filter(json["payload"], fn payload -> payload.kid == kid end)
    # key = JOSE.JWK.from(key_json)
    # {true, _, _} = JOSE.JWS.verify(key, token)

    conn
  end

  defp login_and_redirect(%{conn: conn, message: message, player: player}) do
    conn
    |> PokerExWeb.Auth.login(player)
    |> put_flash(:info, message)
    |> redirect(to: player_path(conn, :show, player.id))
  end

  defp player_params(user_info) do
    %{
      "name" => user_info["name"],
      "email" => user_info["email"],
      "first_name" => user_info["first_name"],
      "last_name" => user_info["last_name"],
      "blurb" => " ",
      "facebook_id" => user_info["id"]
    }
  end

  defp maybe_insert_player(conn, user_info) do
    changeset = PokerEx.Player.facebook_reg_changeset(%PokerEx.Player{}, player_params(user_info))

    case Repo.insert(changeset) do
      {:ok, player} ->
        login_and_redirect(%{
          conn: conn,
          message: "Welcome to PokerEx, #{player.name}",
          player: player
        })

      _error ->
        conn
        |> put_flash(:error, "Signup failed")
        |> redirect(to: "/")
    end
  end
end
