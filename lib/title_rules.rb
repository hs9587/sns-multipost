require "yaml"

module SnsMultipost
  class TitleRules
    DEFAULT_PATH = File.expand_path("../title_rules.yml", __dir__)

    def self.load(path = DEFAULT_PATH)
      new(YAML.safe_load_file(path))
    end

    def initialize(rules)
      @r = rules
    end

    def title_for(text)
      ohayo(text) || coffee(text) || food(text) || fallback(text)
    end

    private

    def ohayo(text)
      hit = @r["ohayo"]["keywords"].any? { |w| text.include?(w) }
      hit ? @r["ohayo"]["title"] : nil
    end

    def coffee(text)
      c = @r["coffee"]
      non_coffee = c["non_coffee_drinks"].any? { |w| text.include?(w) }
      vocab_hit = c["vocab"].any? { |w| text.include?(w) }
      shop_hit = c["shops"].any? { |w| text.include?(w) }
      return nil unless vocab_hit || (shop_hit && !non_coffee)
      return "アイス" if c["iced"].any? { |w| text.include?(w) }
      first_in_text(text, c["brands"]) || "ホット"
    end

    def food(text)
      first_in_text(text, @r["foods"])
    end

    def first_in_text(text, words)
      hits = words.filter_map { |w| (i = text.index(w)) && [i, w] }
      hits.min_by(&:first)&.last
    end

    def fallback(text)
      flat = text.gsub(/\s+/, " ").strip
      len = @r["fallback_length"] || 12
      flat.length <= len ? flat : flat[0, len] + "…"
    end
  end
end
