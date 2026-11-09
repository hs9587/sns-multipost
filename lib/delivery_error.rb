module SnsMultipost
  # The operation has not reached submission and is safe to retry later.
  class DeferredRetryError < RuntimeError; end

  class DeliveryUnknownError < RuntimeError
    def self.wrap(error, context: nil)
      return error if error.is_a?(self)

      prefix = context.to_s.empty? ? "投稿操作後" : context
      new("#{prefix}の結果を確認できません: #{error.message}")
    end
  end
end
