# 投稿結果不明時の重複防止

- 日付: 2026-09-06
- 状態: 実装・自動テスト完了
- 対象: API投稿、mixi、mixi2、Jotter.me、`run_queue`、`retry`

## 問題

投稿操作の後で応答や公開画面の確認に失敗した場合、投稿自体は成立している可能性がある。
この失敗ジョブをそのまま再実行すると二重投稿になり得る。特にJotter.meは公開後の個別画面への
反映が遅れる場合があり、過去に失敗表示の後から投稿が確認できた実例がある。

## 判定

次の失敗を `delivery_state: unknown`（投稿結果不明）として `failed/` のJSONへ記録する。

- POST送信後の読取り・書込みタイムアウト、接続リセット等
- POSTに対するHTTP 408、500、502、503、504
- mixi、mixi2、Jotter.meで送信操作を開始した後の公開確認失敗

HTTPのPOSTにはログイン、トークン更新、画像アップロード、非公開下書き作成もあるため、すべてを
結果不明にはしない。Fedibirdのstatus作成、Blueskyのrecord作成、TumblrとBloggerの公開記事作成、
Threadsのテキスト自動公開とpublish、Xのtweet作成だけを「公開を成立させるPOST」として印付けする。

DNS解決失敗、接続開始タイムアウト、接続拒否など、サーバーへ未送信と判断できる失敗は
`unknown` にしない。送信ボタンを押す前のブラウザ操作失敗も従来どおり再試行可能な失敗とする。

`bin/task` と `bin/failed_jobs` は結果不明ジョブへ `[投稿結果不明]` を付けて表示する。

## 解決手順

まず対象SNSを確認する。未投稿であることを確認できた場合だけ明示的に再試行する。

    ruby bin/retry --confirm-not-posted failed/対象ジョブ.json

すでに投稿されていた場合は再投稿せず、確認済みとして `done/` へ移す。

    ruby bin/retry --confirm-posted failed/対象ジョブ.json

`--confirm-posted` はJSONの `delivery_state` を `confirmed_posted` にして移動する。診断用PNGは
`failed/` に残す。通常の失敗ジョブと、この機能追加前に作られた古い失敗ジョブは、従来どおり
オプションなしの `bin/retry` で再試行できる。

投稿先によって反映遅延や検索精度が異なるため、現段階では全SNSを機械的に検索して「未投稿」と
断定しない。結果不明時の再投稿を止め、人が投稿先を確認して二つの明示操作から選ぶ方式とする。
