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

## Tumblr のトークン

1. https://www.tumblr.com/oauth/apps でアプリを登録し OAuth2 consumer key/secret を取得
2. OAuth2 の認可フローでアクセストークンを取得（scope: write）。取得したトークンを config.yml の `tumblr.access_token` に記入
3. `tumblr.blog_identifier` に投稿先ブログ（例 you.tumblr.com）を記入

## Blogger のトークン

1. Google Cloud Console でプロジェクトを作り、Blogger API v3 を有効化
2. OAuth 同意画面を設定し、OAuth2 クライアント（デスクトップ/ウェブ）を作成 → client_id/client_secret を取得
3. scope `https://www.googleapis.com/auth/blogger` で認可し、refresh token を取得（`access_type=offline`）。config.yml の `blogger.client_id`/`client_secret`/`refresh_token` に記入
4. `blogger.blog_id` に対象ブログの数値ID を記入（Blogger 管理画面のURL等で確認できる）
