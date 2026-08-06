require "yaml"

module SnsMultipost
  class Config
    DEFAULT_PATH = File.expand_path("../config.yml", __dir__)

    def self.load(path = DEFAULT_PATH)
      unless File.exist?(path)
        raise "config.yml がありません。config.sample.yml をコピーして作成してください: #{path}"
      end
      new(YAML.safe_load_file(path))
    end

    def initialize(hash)
      @hash = hash || {}
    end

    def [](key)
      @hash[key.to_s]
    end

    def targets_for(trigger)
      targets = @hash["targets"] || []
      return targets[trigger.to_s] || [] if targets.is_a?(Hash)

      # 旧形式との互換性: 配列の場合、watch だけ Fedibird を除外する。
      trigger == :watch ? targets - ["fedibird"] : targets
    end
  end
end
