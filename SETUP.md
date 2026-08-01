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

Tumblr のアクセストークンは短命で、refresh token で更新する（Tumblr は更新のたびに
refresh token も新しくなる＝ローテーション型なので、新しい refresh token は
state/tumblr_token.json に自動保存される）。

1. https://www.tumblr.com/oauth/apps でアプリを登録し OAuth2 consumer key/secret を取得
2. OAuth2 の認可フローで refresh token を取得（scope: write, offline_access）
3. config.yml の tumblr ブロックに記入:
   - client_id = consumer key
   - client_secret = secret key
   - refresh_token = 取得した refresh token
   - blog_identifier = 投稿先ブログ（例 you.tumblr.com）

復旧: ローテーション型のため、`state/tumblr_token.json` を失う（削除・破損等）と
最新の refresh token も失われる。その場合は手順2の OAuth2 認可フローをやり直して
新しい refresh token を config.yml の `refresh_token` に入れ直す（初回の種として再シードされる）。

## Blogger のトークン

1. Google Cloud Console でプロジェクトを作り、Blogger API v3 を有効化
2. OAuth 同意画面を設定し、OAuth2 クライアント（デスクトップ/ウェブ）を作成 → client_id/client_secret を取得
3. scope `https://www.googleapis.com/auth/blogger` で認可し、refresh token を取得（`access_type=offline`）。config.yml の `blogger.client_id`/`client_secret`/`refresh_token` に記入
4. `blogger.blog_id` に対象ブログの数値ID を記入（Blogger 管理画面のURL等で確認できる）

## X（Twitter）のトークン

X はメディアアップロードが OAuth1.0a 必須のため、投稿も OAuth1.0a に統一する。

1. https://developer.x.com/ でアプリを作成し、アプリ権限を Read and write にする
2. API Key / API Key Secret（= consumer_key / consumer_secret）を取得
3. 同じアプリで Access Token / Access Token Secret を発行（Read and write 権限で）→ access_token / access_token_secret
4. config.yml の `x` ブロックに4つの値と `username`（@ 抜き）を記入
5. 無料枠は投稿数の上限が小さい。枠を使い切ると 429 が返る点に注意

## 常駐運用（Windows タスクスケジューラ）

Fedibird の新着を定期的に検出して各 SNS へ自動展開する。常駐プロセスは持たず、
タスクスケジューラで `bin/watch` -> `bin/run_queue` を数分おきに回す。

### 1. 実行ラッパー（.bat）を用意

リポジトリ外に次の内容で保存する（`<REPO>` は clone 先の絶対パスに置き換え）:

    @echo off
    cd /d <REPO>
    ruby bin\watch      >> logs\cron.log 2>&1
    ruby bin\run_queue  >> logs\cron.log 2>&1

### 2. 仕掛ける前のプリフライト

1. `ruby bin\watch` を1回実行して差分検出の基準を現在に合わせる
2. `del queue\*.json` で、その基準合わせで作られた過去分ジョブを破棄する
   （常駐開始と同時に過去投稿を一斉展開しないため）
3. `config.yml` の `dry_run` を `false` にする（本番スイッチ）
4. `targets` に投稿クレジット等の都合で使わない SNS があれば外しておく

### 3. タスク登録（5分おきの例）

    schtasks /Create /TN "sns-multipost" /TR "<.batの絶対パス>" /SC MINUTE /MO 5 /F

ログオン中に動く。PC がスリープ中は動かないので常時起動の機で運用する。

### 4. 確認・停止・解除

- 動作ログ: `type logs\cron.log`（末尾に `ok=... failed=...`）
- このタスクの確認: `schtasks /Query /TN "sns-multipost" /V /FO LIST`
- 全タスク一覧: `schtasks /Query`（数が多いので `schtasks /Query | findstr sns-multipost` で絞れる）
- 一時無効化: `schtasks /Change /TN "sns-multipost" /DISABLE`（再開は /ENABLE）
- 解除: `schtasks /Delete /TN "sns-multipost" /F`

### 補足

- `bin/watch` は dry_run に関係なくジョブ生成と基準更新を行う（投稿の可否は run_queue 側の dry_run で決まる）
- 自己投稿は state/self_posted.txt で除外されるためループしない
- トークンが期限切れになっても、refresh 対応済みの SNS（Blogger, Tumblr）は自動更新される
