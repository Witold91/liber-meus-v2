module ScenarioCatalog
  SCENARIOS_DIR = Rails.root.join("config", "scenarios")
  LOCALES_DIR = SCENARIOS_DIR.join("locales")

  @@cache = {}

  def self.find(slug, locale: "en")
    slug = slug.to_s
    if locale.to_s != "en"
      @@cache["#{slug}.#{locale}"] || @@cache[slug]
    else
      @@cache[slug]
    end
  end

  def self.find!(slug, locale: "en")
    find(slug, locale: locale) || raise(KeyError, I18n.t("services.scenario_catalog.not_found", slug: slug))
  end

  def self.all
    @@cache.select { |k, _| !k.include?(".") }.values
  end

  def self.reload!
    @@cache = {}

    Dir.glob(SCENARIOS_DIR.join("*.yml")).each do |path|
      data = YAML.load_file(path, symbolize_names: false)
      @@cache[data["slug"]] = data
    end

    Dir.glob(LOCALES_DIR.join("*.yml")).each do |path|
      filename = File.basename(path, ".yml")
      parts = filename.split(".")
      next unless parts.size == 2
      slug, locale = parts
      base = @@cache[slug]
      next unless base
      overlay = YAML.load_file(path, symbolize_names: false)
      @@cache["#{slug}.#{locale}"] = deep_merge_scenario(base, overlay)
    end

    @@cache
  end

  private

  def self.deep_merge_scenario(base, overlay)
    result = base.dup

    %w[title description world_context narrator_style].each do |key|
      result[key] = overlay[key] if overlay.key?(key)
    end

    if overlay.key?("hero") && base.key?("hero")
      hero = base["hero"].dup
      %w[name description].each do |key|
        hero[key] = overlay["hero"][key] if overlay["hero"].key?(key)
      end
      result["hero"] = hero
    end

    if overlay.key?("acts") && base.key?("acts")
      result["acts"] = merge_acts(base["acts"], overlay["acts"])
    end

    result
  end

  def self.merge_acts(base_acts, overlay_acts)
    overlay_by_number = overlay_acts.index_by { |a| a["number"] }

    base_acts.map do |base_act|
      overlay_act = overlay_by_number[base_act["number"]]
      next base_act unless overlay_act

      act = base_act.dup
      %w[title intro].each do |key|
        act[key] = overlay_act[key] if overlay_act.key?(key)
      end

      if overlay_act.key?("scenes") && base_act.key?("scenes")
        act["scenes"] = merge_scenes(base_act["scenes"], overlay_act["scenes"])
      end

      if overlay_act.key?("actors") && base_act.key?("actors")
        act["actors"] = merge_by_key(base_act["actors"], overlay_act["actors"], "id") do |base_item, overlay_item|
          item = base_item.dup
          %w[name description].each do |key|
            item[key] = overlay_item[key] if overlay_item.key?(key)
          end
          item
        end
      end

      if overlay_act.key?("objects") && base_act.key?("objects")
        act["objects"] = merge_by_key(base_act["objects"], overlay_act["objects"], "id") do |base_item, overlay_item|
          item = base_item.dup
          item["name"] = overlay_item["name"] if overlay_item.key?("name")
          item
        end
      end

      if overlay_act.key?("conditions") && base_act.key?("conditions")
        act["conditions"] = merge_by_key(base_act["conditions"], overlay_act["conditions"], "id") do |base_item, overlay_item|
          item = base_item.dup
          item["narrative"] = overlay_item["narrative"] if overlay_item.key?("narrative")
          item
        end
      end

      act
    end
  end

  def self.merge_scenes(base_scenes, overlay_scenes)
    merge_by_key(base_scenes, overlay_scenes, "id") do |base_scene, overlay_scene|
      scene = base_scene.dup
      %w[name description].each do |key|
        scene[key] = overlay_scene[key] if overlay_scene.key?(key)
      end

      if overlay_scene.key?("exits") && base_scene.key?("exits")
        scene["exits"] = merge_by_key(base_scene["exits"], overlay_scene["exits"], "to") do |base_exit, overlay_exit|
          exit_item = base_exit.dup
          exit_item["label"] = overlay_exit["label"] if overlay_exit.key?("label")
          exit_item
        end
      end

      scene
    end
  end

  def self.merge_by_key(base_arr, overlay_arr, key, &block)
    overlay_by_key = overlay_arr.index_by { |item| item[key] }

    base_arr.map do |base_item|
      overlay_item = overlay_by_key[base_item[key]]
      overlay_item ? block.call(base_item, overlay_item) : base_item
    end
  end
end
