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
      modifiers = c["modifiers"] || []
      non_coffee = c["non_coffee_drinks"].any? { |w| text.include?(w) }
      # 明確なコーヒー語（アイス/ホットの温度修飾語を除いた語彙）
      strong = (c["vocab"] - modifiers).any? { |w| text.include?(w) }
      # 温度修飾語や店名のみが手がかりのときは、非コーヒー飲料語があればよける
      weak = modifiers.any? { |w| text.include?(w) } || c["shops"].any? { |w| text.include?(w) }
      return nil unless strong || (weak && !non_coffee)
      return "アイス" if c["iced"].any? { |w| text.include?(w) }
      first_in_text(text, c["brands"]) || "ホット"
    end

    def food(text)
      aliases = @r["food_aliases"] || {}
      first_food_in_text(text, @r["foods_priority"] || [], aliases) ||
        first_food_in_text(text, @r["foods"] || [], aliases)
    end

    def first_food_in_text(text, words, aliases)
      candidates = words.map { |word| [word, word] }
      aliases.each do |variant, canonical|
        candidates << [variant, canonical] if words.include?(canonical)
      end
      hits = candidates.filter_map do |variant, canonical|
        (index = text.index(variant)) && [index, canonical]
      end
      hits.min_by(&:first)&.last
    end

    def first_in_text(text, words)
      hits = words.filter_map { |w| (i = text.index(w)) && [i, w] }
      hits.min_by(&:first)&.last
    end

    def fallback(text)
      flat = text.strip
      len = @r["fallback_length"] || 12
      head = flat[0, len]
      boundary = head.index(/[、。，．,.！？!?\s　]/)
      return head[0, boundary] if boundary&.positive?

      flat.length <= len ? flat : head + "…"
    end
  end
end
