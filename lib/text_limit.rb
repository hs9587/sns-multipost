module SnsMultipost
  module TextLimit
    # SNS 別の本文文字数上限（grapheme 単位）。ここに無い SNS は無制限
    LIMITS = {
      "x" => 280,
      "bluesky" => 300
    }.freeze

    ELLIPSIS = "…".freeze

    # text を sns の上限に収める。超過時は先頭 (limit-1) grapheme + "…"
    def self.fit(text, sns)
      limit = LIMITS[sns]
      return text unless limit
      g = text.grapheme_clusters
      return text if g.length <= limit
      g.first(limit - 1).join + ELLIPSIS
    end
  end
end
