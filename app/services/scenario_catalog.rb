module ScenarioCatalog
  SCENARIOS_DIR = Rails.root.join("config", "scenarios")

  @@cache = {}

  def self.find(slug)
    @@cache[slug.to_s]
  end

  def self.find!(slug)
    find(slug) || raise(KeyError, I18n.t("services.scenario_catalog.not_found", slug: slug))
  end

  def self.all
    @@cache.values
  end

  def self.reload!
    @@cache = {}
    Dir.glob(SCENARIOS_DIR.join("*.yml")).each do |path|
      data = YAML.load_file(path, symbolize_names: false)
      @@cache[data["slug"]] = data
    end
    @@cache
  end
end
