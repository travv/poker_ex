defmodule PokerEx.GameEngine.Server do
  use GenServer
  require Logger
  alias PokerEx.GameEngine.GameEvents
  alias PokerEx.GameEngine.Impl, as: Game
  alias PokerEx.Players.Bank

  @valid_funcs [
    :join,
    :leave,
    :call,
    :check,
    :fold,
    :raise,
    :add_chips,
    :player_count,
    :player_list
  ]

  ##################
  # INITIALIZATION #
  ##################

  def init([]), do: {:ok, %Game{}}
  def init([[id, :private]]), do: {:ok, %Game{type: :private, game_id: id}}
  def init([id]), do: {:ok, %Game{game_id: id}}

  ###############
  # TERMINATION #
  ###############

  def terminate(:normal, %Game{type: :public}), do: :void

  def terminate(_reason, %Game{type: :public, chips: chips, seating: seating})
      when is_map(chips) do
    Logger.warn("Terminating public game and restoring chips to players")
    restore_chips_to_players(chips, seating)
  end

  def terminate(:manual, %Game{chips: chips, seating: seating}) when is_map(chips) do
    restore_chips_to_players(chips, seating)
  end

  def terminate(reason, %Game{type: :private, game_id: id} = game) do
    Logger.warn("Now terminating #{inspect(id)} for reason: #{inspect(reason)}.")
    Logger.warn("Storing game state...")
    PokerEx.PrivateRoom.get_game_and_store_state(id, game)
    :void
  end

  def terminate(_, _), do: :void

  #############
  # CALLBACKS #
  #############

  def handle_call(:no_op, _from, game), do: {:reply, game, game}

  def handle_call({:put_state, new_game}, _from, _game) do
    {:reply, new_game, new_game}
  end

  def handle_call(args, _from, game) do
    [function | arguments] = Tuple.to_list(args)

    case function in @valid_funcs do
      true ->
        with {:ok, game_update} <- apply(Game, function, [game | arguments]) do
          GameEvents.notify_subscribers(game_update)
          {:reply, game_update, game_update}
        else
          {:error, :already_joined} ->
            {:reply, game, game}

          {:error, error} ->
            {:reply, error, game}
        end

      false ->
        Logger.warn("Received an unrecognized function call on game: #{function}")
        {:noreply, game}
    end
  end

  ###########
  # HELPERS #
  ###########

  defp restore_chips_to_players(chips, seating) do
    seating.arrangement
    |> Enum.map(fn {player, _seat_position} -> player end)
    |> Enum.each(fn player ->
      case chips.chip_roll[player.name] do
        nil -> :ok
        _ -> Bank.credit(player, restore_chips(chips, player.name))
      end
    end)
  end

  defp restore_chips(%{chip_roll: chip_roll, paid: paid}, name) do
    case paid[name] do
      nil -> chip_roll[name]
      amount -> chip_roll[name] + amount
    end
  end
end
