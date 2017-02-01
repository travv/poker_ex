defmodule PokerEx.LobbyEvents do
  alias PokerEx.Endpoint
  
  def update_number_players(room, number) do
    Endpoint.broadcast("players:lobby", "update_num_players", %{room: room, number: number})
  end
end