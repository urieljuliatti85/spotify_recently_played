require "test_helper"

class InviteTest < ActiveSupport::TestCase
  test "the raw token is returned once and never stored" do
    invite = Invite.issue!(label: "Ana")

    assert_predicate invite.token, :present?
    assert_not_equal invite.token, invite.token_digest
    assert_nil Invite.find(invite.id).token, "a reloaded invite must not hand the token back"
  end

  test "a token matches only its own invite" do
    invite = Invite.issue!
    Invite.issue!

    assert_equal invite.id, Invite.claimable_by(invite.token).id
    assert_nil Invite.claimable_by("not-a-real-token")
    assert_nil Invite.claimable_by(nil)
    assert_nil Invite.claimable_by("")
  end

  test "claiming spends the invite" do
    account = SpotifyAccount.create!(display_name: "Ana", spotify_user_id: "ana")
    invite = Invite.issue!
    token = invite.token

    invite.claim!(account)

    assert_predicate invite, :claimed?
    assert_equal account, invite.spotify_account
    assert_nil Invite.claimable_by(token), "a spent invite must not be claimable again"
  end

  # The controller checks `claimable_by` before starting the OAuth round trip,
  # but that leaves a real gap: two callbacks can both pass that check before
  # either calls `claim!`. This is what proves the second one loses instead of
  # silently overwriting the first — same instance, claimed twice in a row,
  # standing in for two requests racing each other.
  test "the loser of a race to claim the same invite is told, not left to overwrite the winner" do
    winner = SpotifyAccount.create!(display_name: "Ana", spotify_user_id: "ana")
    loser = SpotifyAccount.create!(display_name: "Bea", spotify_user_id: "bea")
    invite = Invite.issue!

    invite.claim!(winner)

    assert_raises(Invite::AlreadyClaimedError) { invite.claim!(loser) }
    assert_equal winner, invite.reload.spotify_account
  end

  test "an expired invite is not claimable" do
    invite = Invite.issue!(lifetime: -1.second)

    assert_predicate invite, :expired?
    assert_nil Invite.claimable_by(invite.token)
  end

  test "deleting the account leaves the invite record but drops the link" do
    account = SpotifyAccount.create!(display_name: "Ana", spotify_user_id: "ana")
    invite = Invite.issue!
    invite.claim!(account)

    account.destroy

    assert_nil invite.reload.spotify_account_id
    assert_predicate invite, :claimed?
  end
end
