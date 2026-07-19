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
      all = @hash["targets"] || []
      trigger == :watch ? all - ["fedibird"] : all
    end
  end
end
