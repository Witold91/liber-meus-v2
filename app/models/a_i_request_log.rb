class AIRequestLog < ApplicationRecord
  scope :recent, -> { order(created_at: :desc) }
  scope :by_service, ->(name) { where(service_name: name) }
  scope :errors, -> { where.not(error_message: nil) }
end
