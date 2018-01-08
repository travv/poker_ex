defmodule PokerEx.Events do
  alias PokerEx.GameEvents
  alias PokerEx.RoomEvents
  alias PokerEx.TableEvents
  alias PokerEx.LobbyEvents

  def player_joined(room_id, player, position) do
    RoomEvents.player_joined(room_id, player, position)
  end

  def state_updated(room_id, update) do
    GameEvents.state_updated(room_id, update)
  end

  def update_number_players(room_id, number) do
    LobbyEvents.update_number_players(room_id, number)
  end

  def game_started(room_id, room) do
    GameEvents.game_started(room_id, room)
  end

  def advance(room_id, player) do
    TableEvents.advance(room_id, player)
  end

  def card_dealt(room_id, card) do
    TableEvents.card_dealt(room_id, card)
  end

  def flop_dealt(room_id, flop) do
    TableEvents.flop_dealt(room_id, flop)
  end

  def update_seating(room_id, seating) do
    TableEvents.update_seating(room_id, seating)
  end

  def clear_ui(room_id) do
    TableEvents.clear_ui(room_id)
  end

  def clear(room_id, update) do
    GameEvents.clear(room_id, update)
  end

  def game_over(room_id, winner, reward) do
    GameEvents.game_over(room_id, winner, reward)
  end

  def winner_message(room_id, message) do
    GameEvents.winner_message(room_id, message)
  end

  def present_winning_hand(room_id, winning_hand, player, type) do
    GameEvents.present_winning_hand(room_id, winning_hand, player, type)
  end

  def update_player_count(room) do
    LobbyEvents.update_player_count(room)
  end
end