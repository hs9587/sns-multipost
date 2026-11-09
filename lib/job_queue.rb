require "json"
require "securerandom"
require "fileutils"
require "digest"
require "time"
require_relative "atomic_file"

module SnsMultipost
  class Job
    ATTRS = %w[sns text title media_paths media_urls source_url attempts last_error
               delivery_state dedupe_key created_at retry_after].freeze
    attr_accessor(*ATTRS.map(&:to_sym))
    attr_reader :path

    def initialize(hash = nil, path: nil, **kwargs)
      hash = hash || kwargs
      ATTRS.each do |a|
        instance_variable_set("@#{a}", hash[a] || hash[a.to_sym])
      end
      @attempts ||= 0
      @media_paths ||= []
      @media_urls ||= []
      @path = path
    end

    def to_h
      ATTRS.to_h { |a| [a, public_send(a)] }
    end
  end

  class JobQueue
    def initialize(root = File.expand_path("..", __dir__))
      @root = root
      %w[queue done failed].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    end

    def enqueue(job, now: Time.now)
      suffix = job.dedupe_key ? dedupe_suffix(job.dedupe_key) : SecureRandom.hex(2)
      if job.dedupe_key
        existing = find_deduplicated_job(suffix, job.dedupe_key)
        return existing if existing
      end
      name = "#{now.strftime('%Y%m%d-%H%M%S')}_#{job.sns}_#{suffix}.json"
      path = File.join(@root, "queue", name)
      AtomicFile.write(path, JSON.pretty_generate(job.to_h))
      path
    end

    def pending(now: Time.now)
      queued_jobs.reject do |job|
        retry_at = deferred_until(job)
        retry_at && retry_at > now
      end
    end

    def deferred(now: Time.now)
      queued_jobs.select do |job|
        retry_at = deferred_until(job)
        retry_at && retry_at > now
      end
    end

    def complete(job)
      move(job.path, "done")
    end

    def fail(job, error)
      job.attempts += 1
      job.last_error = error.to_s
      job.retry_after = nil
      AtomicFile.write(job.path, JSON.pretty_generate(job.to_h))
      move(job.path, "failed")
    end

    def defer(job, error, retry_after:)
      job.attempts += 1
      job.last_error = error.to_s
      job.retry_after = retry_after.iso8601
      AtomicFile.write(job.path, JSON.pretty_generate(job.to_h))
      job.path
    end

    def requeue(path, confirmed_not_delivered: false)
      if confirmed_not_delivered
        data = JSON.parse(File.read(path))
        data["delivery_state"] = nil
        AtomicFile.write(path, JSON.pretty_generate(data))
      end
      dest = File.join(@root, "queue", File.basename(path))
      FileUtils.mv(path, dest)
      dest
    end

    def resolve_as_posted(path)
      data = JSON.parse(File.read(path))
      data["delivery_state"] = "confirmed_posted"
      AtomicFile.write(path, JSON.pretty_generate(data))
      move(path, "done")
    end

    private

    def queued_jobs
      directory = File.join(@root, "queue")
      Dir.children(directory).select { |name| name.end_with?(".json") }.sort.map do |name|
        path = File.join(directory, name)
        Job.new(JSON.parse(File.read(path)), path: path)
      end
    end

    def deferred_until(job)
      value = job.retry_after.to_s.strip
      return nil if value.empty?

      Time.iso8601(value)
    rescue ArgumentError
      nil
    end

    def dedupe_suffix(key)
      Digest::SHA256.hexdigest(key.to_s)[0, 12]
    end

    def find_deduplicated_job(suffix, key)
      candidates = %w[queue done failed].flat_map do |directory|
        Dir[File.join(@root, directory, "*_#{suffix}.json")]
      end
      candidates.each do |path|
        stored = JSON.parse(File.read(path))
        return path if stored["dedupe_key"] == key
      end
      return nil if candidates.empty?

      raise "ジョブ識別子の衝突を検出しました: #{suffix}"
    end

    def move(src, dir)
      dest = File.join(@root, dir, File.basename(src))
      FileUtils.mv(src, dest)
      dest
    end
  end
end
