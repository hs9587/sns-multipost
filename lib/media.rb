require "fileutils"
require "open-uri"
require "uri"

module SnsMultipost
  module Media
    LIMITS = {
      "fedibird" => 4, "x" => 4, "bluesky" => 4, "tumblr" => 10,
      "blogger" => 20, "instagram" => 10, "mixi" => 1, "mixi2" => 4,
      "jotter" => 0
    }.freeze
    DEFAULT_LIMIT = 1

    def self.limit_for(sns)
      LIMITS.fetch(sns, DEFAULT_LIMIT)
    end

    def self.for_sns(paths, sns)
      paths.first(limit_for(sns))
    end

    def self.download(urls, dest_dir, fetcher: ->(u) { URI.open(u, "rb", &:read) })
      FileUtils.mkdir_p(dest_dir)
      urls.each_with_index.map do |url, i|
        ext = File.extname(URI(url).path)
        ext = ".bin" if ext.empty?
        path = File.join(dest_dir, format("%02d%s", i + 1, ext))
        File.binwrite(path, fetcher.call(url))
        path
      end
    end
  end
end
