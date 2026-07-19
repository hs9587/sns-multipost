require_relative "test_helper"
require "title_rules"

class TitleRulesTest < Minitest::Test
  def setup
    @rules = SnsMultipost::TitleRules.load
  end

  def test_ohayo
    assert_equal "おはよう", @rules.title_for("おはようございます、今朝は晴れ")
  end

  def test_ohayo_wins_over_coffee_and_food
    assert_equal "おはよう", @rules.title_for("おはよう、パンとコーヒー")
  end

  def test_coffee_hot
    assert_equal "ホット", @rules.title_for("コーヒーを一杯")
  end

  def test_coffee_iced
    assert_equal "アイス", @rules.title_for("アイスコーヒーで一息")
  end

  def test_coffee_brand_name
    assert_equal "モカ", @rules.title_for("猫廼舎。イエメン イブラヒム・モカ、特徴が強い")
  end

  def test_shop_name_without_drink_word_is_coffee
    assert_equal "ホット", @rules.title_for("猫廼舎で読書")
  end

  def test_non_coffee_drink_is_not_coffee
    assert_equal "紅茶をいただきながらのん…",
                 @rules.title_for("紅茶をいただきながらのんびり過ごす")
  end

  def test_food_first_in_text_order
    assert_equal "そば", @rules.title_for("まずそば、それからおにぎり")
    assert_equal "パン", @rules.title_for("今日のお昼はパンとスープ")
  end

  def test_fallback_truncates_to_12_chars
    assert_equal "今日は良い天気なので散歩…", @rules.title_for("今日は良い天気なので散歩に出かけました")
  end

  def test_fallback_short_text_as_is
    assert_equal "短い", @rules.title_for("短い")
  end
end
