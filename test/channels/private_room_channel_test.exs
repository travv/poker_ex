defmodule PokerExWeb.PrivateRoomChannelTest do
  use PokerExWeb.ChannelCase, async: false
  import PokerEx.TestHelpers
  alias PokerExWeb.PrivateRoomChannel
  alias PokerEx.PrivateRoom
  alias PokerEx.Player

  @endpoint PokerExWeb.Endpoint
  @players_per_page 25

  setup do
    {socket, player, token, reply, room} = create_player_and_connect()

    {:ok, socket: socket, player: player, token: token, reply: reply, room: room}
  end

  test "join replies with `:success` when authentication is successful", context do
    assert context.reply.response == :success
  end

  test "a `current_rooms` message is pushed on successful joins", context do
    room_process = context.room.title

    expected_current_rooms = %{
      rooms: [%{room: room_process, player_count: 0, is_owner: true}],
      page: 1,
      total_pages: 1
    }

    expected_invited_rooms = %{rooms: [], page: 1, total_pages: 0}

    assert_push(
      "current_rooms",
      %{current_rooms: ^expected_current_rooms, invited_rooms: ^expected_invited_rooms}
    )
  end

  test "a `player_list` message is pushed on successful joins", context do
    first_page_names =
      Player.all()
      |> Stream.map(& &1.name)
      |> Stream.reject(&(&1 == context.player.name))
      |> Enum.take(@players_per_page)

    first_page_names = Enum.reject(first_page_names, &(&1 == context.player.name))

    assert_push("player_list", %{players: ^first_page_names, page: 1, total_pages: _})
  end

  test "`accept_invititation` messages trigger updates to the accepting player's participating_rooms",
       context do
    invited_player = PrivateRoom.preload(context.room) |> Map.get(:invitees) |> hd()

    push(context.socket, "accept_invitation", %{
      "player" => invited_player.name,
      "room" => context.room.title
    })

    Process.sleep(50)
    updated_player = Player.by_name(invited_player.name) |> Player.preload()
    updated_room = PrivateRoom.by_title(context.room.title) |> PrivateRoom.preload()

    assert updated_room.id in Enum.map(updated_player.participating_rooms, & &1.id)
    refute updated_room.id in Enum.map(updated_player.invited_rooms, & &1.id)
  end

  test "`decline_invitation` messages trigger updates to the declining player's invited_rooms",
       context do
    invited_player = PrivateRoom.preload(context.room) |> Map.get(:invitees) |> hd()

    push(context.socket, "decline_invitation", %{
      "player" => invited_player.name,
      "room" => context.room.title
    })

    Process.sleep(50)
    updated_player = Player.by_name(invited_player.name) |> Player.preload()
    updated_room = PrivateRoom.by_title(context.room.title) |> PrivateRoom.preload()

    refute updated_room.id in Enum.map(updated_player.invited_rooms, & &1.id)
    refute updated_room.id in Enum.map(updated_player.invited_rooms, & &1.id)
  end

  test "`create_room` message creates a new room with the given title", context do
    # TODO: Take one of the invited players and `subscribe_and_join` the `notifications_channel:#{name}`
    # for that player. When a `create_room` message is received in the PrivateRoomChannel, it
    # should also trigger a `broadcast` to the NotificationsChannel for each invited player.
    title = "test#{Base.encode16(:crypto.strong_rand_bytes(8))}"

    ref =
      push(context.socket, "create_room", %{
        "title" => title,
        "owner" => context.player.name,
        "invitees" => Enum.map(context.room.invitees, & &1.name)
      })

    # Make sure that the reply has been sent
    assert_reply(ref, :ok)
  end

  test "`create_room` fails and returns an error response if given a duplicate room name",
       context do
    room = PrivateRoom.preload(context.room)
    invitees = Enum.map(context.room.invitees, & &1.name)

    ref =
      push(context.socket, "create_room", %{
        "title" => room.title,
        "owner" => context.player.name,
        "invitees" => invitees
      })

    assert_reply(ref, :error, %{errors: ["Title has already been taken"]})
  end

  test "`get_page` incoming messages triggers accurate responses with updated list data",
       context do
    push(context.socket, "get_page", %{"for" => "current_rooms", "page_num" => 1})

    assert_push("new_current_rooms", %{current_rooms: %{rooms: _, page: 1, total_pages: _}})
  end

  test "`leave_room` messages sends back a `current_rooms` message with updated room data",
       context do
    player = PrivateRoom.preload(context.room) |> Map.get(:invitees) |> hd()

    {socket, player} = connect_other_player(player)

    push(socket, "accept_invitation", %{"player" => player.name, "room" => context.room.title})
    # Ensure the player accepts the invitation to leave the room

    Process.sleep(50)

    push(socket, "leave_room", %{
      "room" => context.room.title,
      "player" => player.name,
      "current_page" => 1
    })

    expected_current_rooms = %{rooms: [], page: 1, total_pages: 0}

    assert_push("current_rooms", %{current_rooms: ^expected_current_rooms, invited_rooms: _})
  end

  test "`delete_room` messages sends back a `current_rooms` message with updated room data",
       context do
    expected_current_rooms = %{rooms: [], page: 1, total_pages: 0}

    push(context.socket, "delete_room", %{
      "room" => context.room.title,
      "player" => context.player.name,
      "current_page" => 1
    })

    assert_push("current_rooms", %{current_rooms: ^expected_current_rooms, invited_rooms: _})
  end

  defp create_player_and_connect do
    player = insert_user()
    invited_players = for _ <- 1..4, do: insert_user()

    {:ok, room} =
      PrivateRoom.create(
        "test#{Base.encode16(:crypto.strong_rand_bytes(8))}",
        player,
        invited_players
      )

    name = player.name
    token = Phoenix.Token.sign(socket(PokerExWeb.UserSocket), "user socket", player.id)

    {:ok, socket} = connect(PokerExWeb.UserSocket, %{"token" => token})

    with {:ok, reply, socket} <-
           subscribe_and_join(socket, PrivateRoomChannel, "private_rooms:" <> name) do
      {socket, player, token, reply, room}
    else
      {:error, reply} -> {socket, player, token, reply, room}
    end
  end

  defp connect_other_player(%Player{} = player) do
    name = player.name
    token = Phoenix.Token.sign(socket(PokerExWeb.UserSocket), "user socket", player.id)

    {:ok, socket} = connect(PokerExWeb.UserSocket, %{"token" => token})

    with {:ok, _reply, socket} <-
           subscribe_and_join(socket, PrivateRoomChannel, "private_rooms:" <> name) do
      {socket, player}
    else
      {:error, reply} -> raise "Connection failed: #{inspect(reply, pretty: true)}"
    end
  end
end
