# SETUP（移設手順書）

本番機（本郷本社 Win11 機）への移設手順。Phase 4 で完成させる。

1. git clone
2. bundle install
3. config.sample.yml を config.yml にコピーして記入
4. （Phase 3 以降）playwright ブラウザ install と各サービスへの初回手動ログイン
5. （Phase 4）タスクスケジューラ登録

## Bluesky のトークン

1. Bluesky にログイン → 設定 → プライバシーとセキュリティ → アプリパスワード → 追加
2. 発行された app password を config.yml の `bluesky.app_password` に記入
3. `bluesky.handle` に自分のハンドル（例 you.bsky.social）を記入
