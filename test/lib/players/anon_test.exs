defmodule PokerEx.Players.AnonTest do
  alias PokerEx.Players.Anon
  import PokerEx.TestHelpers
  use ExUnit.Case

  describe "new/1" do
    test "creates an Anon player" do
      assert {:ok, %Anon{}} = Anon.new(%{"name" => "Player: #{random_string()}"})
    end

    test "generates a guest_id for the new player" do
      assert {:ok, %Anon{guest_id: guest_id}} = Anon.new(%{"name" => "Anon user"})

      assert String.starts_with?(guest_id, "Anon user_GUEST_")
    end

    test "defaults the chip count to 1000" do
      assert {:ok, %Anon{chips: 1000}} = Anon.new(%{"name" => "Anon user"})
    end

    test "returns an error tuple if no name is given" do
      assert {:error, :missing_name} = Anon.new(%{"nombe" => "nope"})
    end
  end

  describe "bet/2" do
    test "takes a number of chips and subtracts that number from the player\'s chip count" do
      {:ok, player} = Anon.new(%{"name" => "A"})

      assert {:ok, %Anon{chips: 800}} = Anon.bet(player, 200)
    end

    test "only allows a player to bet up to the number of chips that they have" do
      {:ok, player} = Anon.new(%{"name" => "A"})

      assert {:ok, %Anon{chips: 0}} = Anon.bet(player, 100_000)
    end

    test "does not allow players to bet negative amounts" do
      {:ok, player} = Anon.new(%{"name" => "A"})

      assert :error = Anon.bet(player, -2000)
    end
  end
end
