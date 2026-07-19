# sns-multipost

きっかけ投稿（Fedibird [@hs9587](https://fedibird.com/@hs9587)）を検出し、
同一内容を複数の SNS へ自動投稿するツール。作りはじめの宣言としてまず公開する。

旧 [SNS_multi_post](https://github.com/hs9587/SNS_multi_post)（Ruby+Selenium 世代）の後継として、
ファイルキュー方式で全面的に作り直すもの。

## やること・やりたいこと

- 投稿先: X / Instagram（連携で Facebook・Threads へ）/ mixi / mixi2 / Bluesky /
  Blogger / Tumblr / Jotter.me
- 入口は Fedibird。きっかけ投稿がそのまま Fedibird への投稿を兼ねる
- 構成は「トリガ → ファイルキュー → 投稿実行」の分離。非常駐、壊れた所だけ直せる作り
- タイトル欄のある SNS（Blogger、mixi 日記など）向けに、本文からタイトルを導く辞書を育てる
- 全 Ruby。ブラウザ操作が要る SNS は playwright-ruby-client

## 進め方

- Phase 1: 基盤＋Fedibird 一気通貫（いまここ）
- Phase 2: API 組ポスター（Bluesky / Tumblr / Blogger / X）
- Phase 3: ブラウザ組（Instagram / mixi / mixi2 / Jotter.me）
- Phase 4: 手順書整備・本番運用

構成・使い方は実装の進行に合わせて追記する。
