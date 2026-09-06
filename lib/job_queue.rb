require "json"
require "securerandom"
require "fileutils"
require_relative "atomic_file"

module SnsMultipost
  class Job
    ATTRS = %w[sns text title media_paths media_urls source_url attempts last_error
               delivery_state created_at].freeze
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
      name = "#{now.strftime('%Y%m%d-%H%M%S')}_#{job.sns}_#{SecureRandom.hex(2)}.json"
      path = File.join(@root, "queue", name)
      AtomicFile.write(path, JSON.pretty_generate(job.to_h))
      path
    end

    def pending
      Dir[File.join(@root, "queue", "*.json")].sort.map do |p|
        Job.new(JSON.parse(File.read(p)), path: p)
      end
    end

    def complete(job)
      move(job.path, "done")
    end

    def fail(job, error)
      job.attempts += 1
      job.last_error = error.to_s
      AtomicFile.write(job.path, JSON.pretty_generate(job.to_h))
      move(job.path, "failed")
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

    def move(src, dir)
      dest = File.join(@root, dir, File.basename(src))
      FileUtils.mv(src, dest)
      dest
    end
  end
end
