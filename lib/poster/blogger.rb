# lib/poster/blogger.rb
require "cgi"
require_relative "base"
require_relative "../blogger_api"
require_relative "../blogger_image_browser"
require_relative "../blogger_image_store"
require_relative "../oauth_refresh"
require_relative "../media"

module SnsMultipost
  module Poster
    class Blogger < Base
      GOOGLE_TOKEN_URI = "https://oauth2.googleapis.com/token".freeze

      def initialize(config, api: nil, image_store: nil)
        super(config)
        @api = api
        @image_store = image_store
      end

      def perform(job)
        paths = Media.for_sns(job.media_paths || [], "blogger")
        source_urls = Media.for_sns(job.media_urls || [], "blogger")
        urls =
          if paths.empty? && source_urls.empty?
            []
          else
            image_store.urls_for(
              media_paths: paths,
              media_urls: source_urls,
              failure_screenshot_path: failure_screenshot_path(job))
          end
        html = build_html(job.text.to_s, urls)
        res = api.insert_post(title: title_for(job), html: html)
        { id: res["id"], url: res["url"] }
      end

      private

      def title_for(job)
        t = job.title.to_s.strip
        t.empty? ? job.text.to_s.strip[0, 30].to_s : t
      end

      def build_html(text, image_urls)
        paragraphs = CGI.escapeHTML(text).split(/\n{2,}/).map do |para|
          "<p>#{para.gsub("\n", "<br>\n")}</p>"
        end
        imgs = image_urls.map { |u| "<img src=\"#{CGI.escapeHTML(u)}\">" }
        (paragraphs + imgs).join("\n")
      end

      def api
        @api ||= begin
          c = @config["blogger"]
          token = OAuthRefresh.access_token(
            token_uri: GOOGLE_TOKEN_URI,
            client_id: c["client_id"], client_secret: c["client_secret"],
            refresh_token: c["refresh_token"])
          BloggerApi.new(blog_id: c["blog_id"], access_token: token)
        end
      end

      def image_store
        @image_store ||= begin
          settings = @config["blogger"] || {}
          browser = BloggerImageBrowser.new(blog_id: settings["blog_id"])
          BloggerImageStore.new(api: api, browser: browser)
        end
      end

      def failure_screenshot_path(job)
        return nil unless job.respond_to?(:path) && job.path
        root = File.dirname(File.dirname(job.path))
        basename = File.basename(job.path, File.extname(job.path))
        File.join(root, "failed", "#{basename}.png")
      end
    end

    register "blogger", Blogger
  end
end
