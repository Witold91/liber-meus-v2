class User < ApplicationRecord
  has_many :games, dependent: :nullify
  has_many :saves, dependent: :destroy

  validates :email,      presence: true, uniqueness: true
  validates :google_uid, presence: true, uniqueness: true
  validates :tokens_remaining, numericality: { greater_than_or_equal_to: 0 }

  def deduct_tokens!(amount)
    new_balance = [ tokens_remaining - amount.to_i, 0 ].max
    update!(tokens_remaining: new_balance)
  end

  def out_of_tokens?
    tokens_remaining <= 0
  end

  def deleted?
    deleted_at.present?
  end
end
