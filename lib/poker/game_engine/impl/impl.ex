defmodule PokerEx.GameEngine.Impl do
  alias PokerEx.{Player, Events}

  alias PokerEx.GameEngine.{
    ChipManager,
    Seating,
    PlayerTracker,
    CardManager,
    ScoreManager,
    PhaseManager,
    RoleManager,
    AsyncManager,
    GameResetCoordinator,
    GameState
  }

  alias __MODULE__, as: Engine
  @timeout 30_000
  @type success :: {:ok, t()}
  @type error :: {:error, atom()}
  @type result :: success | error
  @type phase :: :idle | :pre_flop | :flop | :turn | :river | :game_over | :between_rounds
  @type t :: %Engine{
          chips: ChipManager.t(),
          seating: Seating.t(),
          type: :private | :public,
          player_tracker: PlayerTracker.t(),
          cards: CardManager.t(),
          scoring: ScoreManager.t(),
          async_manager: AsyncManager.t(),
          game_id: String.t() | :none,
          roles: RoleManager.t(),
          timeout: pos_integer,
          phase: phase
        }

  @derive Jason.Encoder
  defstruct chips: ChipManager.new(),
            seating: Seating.new(),
            player_tracker: PlayerTracker.new(),
            cards: CardManager.new(),
            scoring: ScoreManager.new(),
            roles: RoleManager.new(),
            async_manager: AsyncManager.new(),
            type: :public,
            game_id: :none,
            phase: :idle,
            timeout: @timeout

  defdelegate decode(value), to: PokerEx.GameEngine.Decoders.Engine

  def new do
    %Engine{}
  end

  @spec join(t(), Player.t(), non_neg_integer) :: result()
  def join(%{phase: initial_phase} = engine, player, chip_amount) do
    with {:ok, new_seating} <- Seating.join(engine, player),
         {:ok, chips} <- ChipManager.join(engine, player, chip_amount),
         phase <- PhaseManager.check_phase_change(engine, :join, new_seating) do
      Events.update_player_count(engine)

      {:ok,
       GameState.update(engine, [
         {:update_seating, new_seating},
         {:update_chips, chips},
         {:set_active_players, initial_phase},
         {:maybe_update_cards, initial_phase, phase},
         {:update_phase, phase},
         :set_roles,
         {:maybe_post_blinds, initial_phase, phase}
       ])}
    else
      error -> error
    end
  end

  @spec call(t(), Player.name()) :: result()
  def call(%{phase: initial_phase} = engine, player) do
    with {:ok, chips} <- ChipManager.call(engine, player),
         {:ok, player_tracker} <- PlayerTracker.call(engine, player, chips),
         phase <- PhaseManager.check_phase_change(engine, :bet, player_tracker) do
      {:ok,
       GameState.update(engine, [
         {:update_chips, chips},
         {:update_tracker, player_tracker},
         {:maybe_update_cards, initial_phase, phase},
         {:update_phase, phase}
       ])}
      |> and_then(:process_async_auto_actions)
      |> and_then(:cleanup_round, initial_phase)
      |> and_then(:maybe_reset_game)
    else
      error -> error
    end
  end

  @spec raise(t(), Player.name(), non_neg_integer) :: result()
  def raise(%{phase: initial_phase} = engine, player, amount) do
    with {:ok, chips} <- ChipManager.raise(engine, player, amount),
         {:ok, player_tracker} <- PlayerTracker.raise(engine, player, chips),
         phase <- PhaseManager.check_phase_change(engine, :bet, player_tracker) do
      {:ok,
       GameState.update(engine, [
         {:update_chips, chips},
         {:update_tracker, player_tracker},
         {:maybe_update_cards, initial_phase, phase},
         {:update_phase, phase}
       ])}
      |> and_then(:process_async_auto_actions)
      |> and_then(:cleanup_round, initial_phase)
      |> and_then(:maybe_reset_game)
    else
      error -> error
    end
  end

  @spec check(t(), Player.name()) :: result()
  def check(%{phase: initial_phase} = engine, player) do
    with {:ok, chips} <- ChipManager.check(engine, player),
         {:ok, player_tracker} <- PlayerTracker.check(engine, player),
         phase <- PhaseManager.check_phase_change(engine, :bet, player_tracker) do
      {:ok,
       GameState.update(engine, [
         {:update_chips, chips},
         {:update_tracker, player_tracker},
         {:maybe_update_cards, initial_phase, phase},
         {:update_phase, phase}
       ])}
      |> and_then(:process_async_auto_actions)
      |> and_then(:cleanup_round, initial_phase)
      |> and_then(:maybe_reset_game)
    else
      error -> error
    end
  end

  @spec fold(t(), Player.name()) :: result()
  def fold(%{phase: initial_phase} = engine, player) do
    with {:ok, player_tracker} <- PlayerTracker.fold(engine, player),
         {:ok, card_manager} <- CardManager.fold(engine, player),
         phase <- PhaseManager.check_phase_change(engine, :bet, player_tracker) do
      {:ok,
       GameState.update(engine, [
         {:update_tracker, player_tracker},
         {:update_cards, card_manager},
         {:maybe_update_cards, initial_phase, phase},
         {:update_phase, phase}
       ])}
      |> and_then(:process_async_auto_actions)
      |> and_then(:cleanup_round, initial_phase)
      |> and_then(:maybe_reset_game)
    else
      error -> error
    end
  end

  @spec leave(t(), Player.name()) :: result()
  def leave(%{phase: phase} = engine, player) when phase in [:idle, :between_rounds] do
    with {:ok, chips} <- ChipManager.leave(engine, player),
         {:ok, player_tracker} <- PlayerTracker.leave(engine, player),
         seating <- Seating.leave(engine, player) do
      {:ok,
       GameState.update(engine, [
         {:update_chips, chips},
         {:update_tracker, player_tracker},
         {:update_seating, seating}
       ])}
    else
      error -> error
    end
  end

  def leave(%{phase: initial_phase} = engine, player) do
    {:ok,
     %__MODULE__{engine | async_manager: AsyncManager.mark_for_action(engine, player, :leave)}}
    |> and_then(:process_async_auto_actions)
    |> and_then(:cleanup_round, initial_phase)
    |> and_then(:maybe_reset_game)
  end

  @spec player_count(t()) :: non_neg_integer
  def player_count(engine) do
    length(engine.seating.arrangement)
  end

  @spec player_list(t()) :: [String.t()]
  def player_list(engine) do
    for {player, _} <- engine.seating.arrangement, do: player
  end

  @spec add_chips(t(), Player.name(), pos_integer) :: success()
  def add_chips(engine, player, amount) do
    {:ok,
     %__MODULE__{
       engine
       | async_manager: AsyncManager.mark_for_action(engine, player, {:add_chips, amount})
     }}
  end

  @spec reset_round(t()) :: t()
  def reset_round(engine) do
    %__MODULE__{
      engine
      | chips: ChipManager.reset_round(engine.chips),
        player_tracker: PlayerTracker.reset_round(engine.player_tracker)
    }
  end

  # This function clause is triggered after successful poker betting actions
  # (call, raise, check, and fold). It removes any players that have been marked
  # to leave and updates the phase if appropriate. It is also triggered after leaves
  # to handle the case in which the leaving player is active. This will auto fold or
  # auto check for the player.
  defp and_then(
         {:ok, %{async_manager: %{cleanup_queue: []}} = engine},
         :process_async_auto_actions
       ) do
    {:ok, engine}
  end

  defp and_then({:ok, %{phase: initial_phase} = engine}, :process_async_auto_actions) do
    with {:ok, engine} <- AsyncManager.run(engine, :cleanup),
         phase <- PhaseManager.check_phase_change(engine, :bet, engine.player_tracker) do
      {:ok,
       GameState.update(engine, [
         {:maybe_update_cards, initial_phase, phase},
         {:update_phase, phase}
       ])}
    else
      error -> error
    end
  end

  # This function clause will reset the game engine implementation struct to a
  # clean state and prepare for a new game only if the phase is :game_over.
  # Otherwise this clause is a no-op.
  defp and_then({:ok, %{phase: :game_over} = engine}, :maybe_reset_game) do
    {:ok, GameResetCoordinator.coordinate_reset(engine)}
  end

  defp and_then({:ok, engine}, _), do: {:ok, engine}

  # This function clause will trigger any necessary cleanup after transitioning
  # from one phase to the next. If there is no phase transition, then this
  # clause is effectively a no-op.
  defp and_then({:ok, %{phase: current_phase} = engine}, :cleanup_round, initial_phase)
       when current_phase != initial_phase do
    {:ok, reset_round(engine)}
  end

  defp and_then({:ok, engine}, :cleanup_round, _), do: {:ok, engine}
end
