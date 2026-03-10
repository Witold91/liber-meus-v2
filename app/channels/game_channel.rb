class GameChannel < ApplicationCable::Channel
  def subscribed
    game = current_user.games.find_by(id: params[:game_id])
    if game
      stream_for game
    else
      reject
    end
  end
end
