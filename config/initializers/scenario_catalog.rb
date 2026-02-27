Rails.application.config.to_prepare do
  ScenarioCatalog.reload!
end
