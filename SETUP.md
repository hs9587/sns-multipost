# SETUP（移設手順書）

Windows 11 機への移設・認証・常駐運用手順。
API 組の移設とタスクスケジューラ運用は実施済み。ブラウザ組は未実装のため、
各サービスのポスター完成時に初回ログイン手順を追記する。

1. git clone
2. bundle install
3. config.sample.yml を config.yml にコピーして記入
4. `ruby bin/watch --sync-only` で Fedibird の監視基準を現在へ合わせる
5. タスクスケジューラ登録

将来ブラウザ組を有効にするときは、採用したブラウザ操作ライブラリをインストールし、
移設先のブラウザでログイン状態を新しく作る。cookie やブラウザプロファイルは別機体からコピーしない。

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
5. 現在のアカウントは Pay Per Use 契約で、クレジットがない場合は 402
   `credits depleted` になる。認証確認は完了しているが、ライブ投稿にはクレジット購入が必要

## Threads のトークン

Threads は公式 Threads API と OAuth2 を使う。投稿権限は `threads_basic` と
`threads_content_publish`。長期アクセストークンは約60日で、期限の7日前から
`state/threads_token.json` へ自動更新・保存する。

1. Meta for Developers でアプリを作成し、Threads のユースケースを追加する
2. Threads API設定の OAuth Redirect URI に、例として
   `https://localhost/threads/callback` を登録する
3. `config.yml` の `threads` ブロックへ `app_id`、`app_secret`、登録した
   `redirect_uri` を記入する
4. 認可URLを表示する:

       ruby bin/threads_auth --authorize

5. 表示されたURLをブラウザで開いて認可する。localhostへの移動に失敗しても、
   アドレスバーに `code` と `state` を含む戻り先URLが表示されればよい
6. アドレスバーの戻り先URL全体を渡す:

       ruby bin/threads_auth --callback "https://localhost/threads/callback?code=...&state=..."

7. `Threadsの長期アクセストークンを保存しました` と表示されたら、
   `targets.post` に `threads` を追加する

認証情報と長期トークンは表示・Git管理しない。認可をやり直す場合も
`--authorize` から開始し、新しい `state` を使う。

## 常駐運用（Windows タスクスケジューラ）

Fedibird の新着を定期的に検出して各 SNS へ自動展開する。常駐プロセスは持たず、
タスクスケジューラで `bin/watch` -> `bin/run_queue` を数分おきに回す。

### 1. 実行ラッパー（.bat）を用意

リポジトリ外に次の内容で保存する（`<REPO>`・`<RUBY>` は実際の絶対パスに置き換え）。
タスクスケジューラ実行時は PATH や cwd が対話シェルと異なることがあるため、
**ruby もログも絶対パスで書く**（相対パスだと「タスクは動くがログも出ず exit 1」になりやすい）:

    @echo off
    set "REPO=<REPO>"
    set "RUBY=<RUBY>\ruby.exe"
    set "LOG=%REPO%\logs\cron.log"
    cd /d "%REPO%" || (echo [%date% %time%] cd FAILED errorlevel=%errorlevel%>>"%LOG%" ^& exit /b 9)
    echo [%date% %time%] start cwd=%CD%>>"%LOG%"
    "%RUBY%" "%REPO%\bin\watch"     >>"%LOG%" 2>&1
    "%RUBY%" "%REPO%\bin\run_queue" >>"%LOG%" 2>&1
    echo [%date% %time%] end>>"%LOG%"

`<RUBY>` は `(Get-Command ruby).Source` の入っているディレクトリ（例 `C:\Ruby33-x64\bin`）。

### 2. 仕掛ける前のプリフライト

1. `ruby bin\watch --sync-only` を1回実行して差分検出の基準を現在に合わせる
   （キューを作らないので、常駐開始と同時に過去投稿を一斉展開しない。
   従来の「watch → `del queue\*.json`」の2手順を1手順に置き換えたもの）
2. `config.yml` の `dry_run` を `false` にする（本番スイッチ）
3. `targets.watch` と `targets.post` から、投稿クレジット等の都合で使わない SNS があれば外しておく

### 3. タスク登録（5分おきの例）

    schtasks /Create /TN "sns-multipost" /TR "<.batの絶対パス>" /SC MINUTE /MO 5 /F

ログオン中に動く。PC がスリープ中は動かないので常時起動の機で運用する。

`schtasks /Create` の既定は **バッテリ運用中は起動抑止**（ノートPCだと電源を抜くと止まる）。
常時動かすなら登録後に外す（PowerShell、トリガ/プリンシパルは維持される）:

    $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    Set-ScheduledTask -TaskName "sns-multipost" -Settings $s

登録直後は `schtasks /Run /TN "sns-multipost"` で1回手動起動し、`logs\cron.log` の先頭に
`start cwd=<REPO>` が出ること（cwd がリポジトリに入っていること）を確認しておくとよい。

### 4. 確認・停止・解除

`schtasks` はネイティブ exe なので PowerShell / cmd どちらで打ってもよい（`/Create` と同じ場所でよい）。
`Set-ScheduledTask`（PowerShell）と `schtasks` は同じタスクを触るので混在しても問題ない。

- 動作ログ: `type logs\cron.log`（末尾に `ok=... failed=...`）
- このタスクの確認: `schtasks /Query /TN "sns-multipost" /V /FO LIST`
- 全タスク一覧: `schtasks /Query`（数が多いので `schtasks /Query | findstr sns-multipost` で絞れる）
- 一時停止 / 再開（スケジュール自体のオンオフ）: `schtasks /Change /TN "sns-multipost" /DISABLE`（再開は /ENABLE）
- 今すぐ1回手動起動（動作テスト）: `schtasks /Run /TN "sns-multipost"`
  （dry_run=false のときは実投稿しうる。queue に何かある状態で打つと即投稿されるので注意）
- 走行中の回を打ち切る: `schtasks /End /TN "sns-multipost"`（10分の処理が長引いた時用。普段は使わない）
- 解除（完全削除）: `schtasks /Delete /TN "sns-multipost" /F`

普段の「止める／動かす」は DISABLE / ENABLE。`/Run` はテスト用、`/End` は打ち切り用。

### 補足

- `bin/watch` は dry_run に関係なくジョブ生成と基準更新を行う（投稿の可否は run_queue 側の dry_run で決まる）
- `bin/watch --sync-only` はキューを作らず since_id だけ最新へ前進させる（基準合わせ専用。運用中に「今の新着は流さず基準だけ合わせ直したい」ときにも使える）
- 自己投稿は state/self_posted.txt で除外されるためループしない
- トークンが期限切れになっても、refresh 対応済みの SNS（Blogger, Tumblr）は自動更新される
