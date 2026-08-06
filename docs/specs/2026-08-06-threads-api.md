# Threads API テキスト投稿

- 日付: 2026-08-06
- 状態: 実装・自動テスト完了、OAuth設定と実投稿確認待ち
- 対象入口: `bin/post` のみ（`targets.post`）

## 方針

Threads はブラウザ操作ではなく、Meta公式 Threads API を使う。
テキスト投稿は `POST https://graph.threads.net/me/threads` に
`media_type=TEXT` と `auto_publish_text=true` を指定して公開する。

認証スコープは `threads_basic,threads_content_publish`。`bin/threads_auth` が
認可URL生成、認可コード交換、短期トークンから長期トークンへの交換を行い、
`state/threads_token.json` に保存する。長期トークンは期限の7日前から更新する。

## 実装

- `lib/threads_api.rb`: テキスト投稿HTTPクライアント
- `lib/threads_oauth.rb`: 認可URL、コード交換、長期化、更新
- `lib/threads_token.rb`: 保存トークンの選択と期限前更新
- `lib/poster/threads.rb`: 500 graphemeへの切り詰めとポスター登録
- `bin/threads_auth`: 初回OAuthの2段階補助

画像投稿は今回の対象外。Facebook個人プロフィールは公式投稿APIの対象外なので、
Phase 3のブラウザ投稿として扱う。

公式資料: https://www.postman.com/meta/threads/documentation/dht3nzz/threads-api
