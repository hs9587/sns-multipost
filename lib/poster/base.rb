module SnsMultipost
  module Poster
    REGISTRY = {}

    def self.register(name, klass)
      REGISTRY[name] = klass
    end

    def self.for(name, config)
      klass = REGISTRY.fetch(name) { raise "poster 未実装: #{name}" }
      klass.new(config)
    end

    class Base
      def initialize(config)
        @config = config
      end

      def post(job)
        return dry_report(job) if @config["dry_run"]
        perform(job)
      end

      def perform(job)
        raise NotImplementedError
      end

      private

      def dry_report(job)
        { dry_run: true, sns: job.sns, title: job.title, text_head: job.text.to_s[0, 40] }
      end
    end
  end
end
