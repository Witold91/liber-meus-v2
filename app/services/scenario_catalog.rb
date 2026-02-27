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

    %w[title description].each do |key|
      result[key] = overlay[key] if overlay.key?(key)
    end

    if overlay.key?("hero") && base.key?("hero")
      hero = base["hero"].dup
      %w[name description].each do |key|
        hero[key] = overlay["hero"][key] if overlay["hero"].key?(key)
      end
      result["hero"] = hero
    end

    if overlay.key?("chapters") && base.key?("chapters")
      result["chapters"] = merge_chapters(base["chapters"], overlay["chapters"])
    end

    result
  end

  def self.merge_chapters(base_chapters, overlay_chapters)
    overlay_by_number = overlay_chapters.index_by { |c| c["number"] }

    base_chapters.map do |base_chapter|
      overlay_chapter = overlay_by_number[base_chapter["number"]]
      next base_chapter unless overlay_chapter

      chapter = base_chapter.dup
      %w[title intro].each do |key|
        chapter[key] = overlay_chapter[key] if overlay_chapter.key?(key)
      end

      if overlay_chapter.key?("stages") && base_chapter.key?("stages")
        chapter["stages"] = merge_stages(base_chapter["stages"], overlay_chapter["stages"])
      end

      if overlay_chapter.key?("actors") && base_chapter.key?("actors")
        chapter["actors"] = merge_by_key(base_chapter["actors"], overlay_chapter["actors"], "id") do |base_item, overlay_item|
          item = base_item.dup
          %w[name description].each do |key|
            item[key] = overlay_item[key] if overlay_item.key?(key)
          end
          item
        end
      end

      if overlay_chapter.key?("objects") && base_chapter.key?("objects")
        chapter["objects"] = merge_by_key(base_chapter["objects"], overlay_chapter["objects"], "id") do |base_item, overlay_item|
          item = base_item.dup
          item["name"] = overlay_item["name"] if overlay_item.key?("name")
          item
        end
      end

      if overlay_chapter.key?("conditions") && base_chapter.key?("conditions")
        chapter["conditions"] = merge_by_key(base_chapter["conditions"], overlay_chapter["conditions"], "id") do |base_item, overlay_item|
          item = base_item.dup
          item["narrative"] = overlay_item["narrative"] if overlay_item.key?("narrative")
          item
        end
      end

      chapter
    end
  end

  def self.merge_stages(base_stages, overlay_stages)
    merge_by_key(base_stages, overlay_stages, "id") do |base_stage, overlay_stage|
      stage = base_stage.dup
      %w[name description].each do |key|
        stage[key] = overlay_stage[key] if overlay_stage.key?(key)
      end

      if overlay_stage.key?("exits") && base_stage.key?("exits")
        stage["exits"] = merge_by_key(base_stage["exits"], overlay_stage["exits"], "to") do |base_exit, overlay_exit|
          exit_item = base_exit.dup
          exit_item["label"] = overlay_exit["label"] if overlay_exit.key?("label")
          exit_item
        end
      end

      stage
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
