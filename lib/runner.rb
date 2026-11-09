require_relative "job_queue"
require_relative "poster/base"
require_relative "delivery_error"

module SnsMultipost
  class Runner
    DEFERRED_RETRY_DELAY = 10 * 60

    def self.exit_status(results)
      results.any? { |result| result[1] == :failed } ? 1 : 0
    end

    def initialize(config:, queue:, clock: -> { Time.now },
                   deferred_retry_delay: DEFERRED_RETRY_DELAY)
      @config = config
      @queue = queue
      @clock = clock
      @deferred_retry_delay = deferred_retry_delay
    end

    def run(jobs = @queue.pending)
      jobs.map do |job|
        begin
          result = Poster.for(job.sns, @config).post(job)
          @queue.complete(job)
          [job, :ok, result]
        rescue StandardError => e
          if defer_once?(job, e)
            retry_after = @clock.call + @deferred_retry_delay
            @queue.defer(job, "#{e.class}: #{e.message}", retry_after: retry_after)
            [job, :deferred, { error: e.message, retry_after: retry_after.iso8601 }]
          else
            job.delivery_state = "unknown" if e.is_a?(DeliveryUnknownError)
            @queue.fail(job, "#{e.class}: #{e.message}")
            [job, :failed, e.message]
          end
        end
      end
    end

    private

    def defer_once?(job, error)
      error.is_a?(DeferredRetryError) && job.attempts.to_i.zero? &&
        job.delivery_state.to_s.empty?
    end
  end
end
