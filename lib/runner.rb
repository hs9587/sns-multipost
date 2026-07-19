require_relative "job_queue"
require_relative "poster/base"

module SnsMultipost
  class Runner
    def initialize(config:, queue:)
      @config = config
      @queue = queue
    end

    def run(jobs = @queue.pending)
      jobs.map do |job|
        begin
          result = Poster.for(job.sns, @config).post(job)
          @queue.complete(job)
          [job, :ok, result]
        rescue StandardError => e
          @queue.fail(job, "#{e.class}: #{e.message}")
          [job, :failed, e.message]
        end
      end
    end
  end
end
