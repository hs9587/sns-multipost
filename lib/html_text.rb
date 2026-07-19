require "cgi"

module SnsMultipost
  module HtmlText
    def self.to_text(html)
      t = html.gsub(%r{<br\s*/?>}i, "\n")
      t = t.gsub(%r{</p>\s*<p>}i, "\n\n")
      t = t.gsub(/<[^>]+>/, "")
      CGI.unescapeHTML(t).strip
    end
  end
end
