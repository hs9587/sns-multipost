# sns-multipost API組ポスター 設計・実装記録

- 日付: 2026-07-20
- 状態: 実装完了・実投稿確認済み。X APIは認証確認のみで終了し、課金・ブラウザ自動化は行わない
- 前提: `Poster::Base` パターン、ファイルキュー、injected transport、config.ymlの基盤を利用
- リポジトリ: GitHub `hs9587/sns-multipost`（既存 main に追加）

## 1. 目的

確立済みの基盤へ、APIで投稿できる4 SNSのポスターを追加する。動機はMT変換機の開発データ作成、すなわち「いろんなSNSに投稿している状態」を作ることにある。

## 2. スコープと順序

API組4ポスターを**認証の軽い順に1本ずつ**追加した:

**Bluesky → Tumblr → Blogger → X**

各ポスターは `Poster::Base` を継承し `Poster.register("<sns>", 自クラス)` で登録する。`bin/run_queue` はレジストリ経由なので登録するだけで処理対象になる。`lib/poster/all.rb` に require を追記する。

## 3. 認証

すべて `config.yml` に値を置き、開発作業では内容を参照しない。トークンの初回取得は外部（各開発者コンソール等）で行う。

| SNS | 認証 | config.yml のキー |
|-----|------|------------------|
| Bluesky | アプリパスワードで `com.atproto.server.createSession` → accessJwt | `handle`, `app_password` |
| Tumblr | OAuth2 Bearer（refresh token ローテーション対応） | `client_id`, `client_secret`, `refresh_token`, `blog_identifier` |
| Blogger | Google OAuth2（refresh 運用） | `client_id`, `client_secret`, `refresh_token`, `blog_id` |
| X | OAuth1.0a User Context | `consumer_key`, `consumer_secret`, `access_token`, `access_token_secret`, `username` |

Blogger は投稿時に refresh token からアクセストークンを取得する。Tumblr はアクセストークンと
refresh token の両方が更新されるため、`TumblrToken` と `TokenStore` が新しい組を
`state/tumblr_token.json` に保存する。X はメディアアップロードの制約から OAuth1.0a に統一し、
期限のないユーザートークンを使う。対話型 OAuth の内蔵はしない。

## 4. 各ポスターの投稿と画像

画像入りで実装する。Bluesky / Tumblr / X は watch がダウンロードしたローカルファイル
（ジョブの `media_paths`）を使う。Bloggerもローカル画像を優先し、ない場合は `media_urls` から
一時取得してBlogger内部画像ストアへアップロードする。
`Media.for_sns` で SNS 別の枚数上限に切り詰める。

- **Bluesky**: `com.atproto.repo.uploadBlob` で画像を上げ、`app.bsky.feed.post` レコードに embed（images）。テキスト上限 300 grapheme、画像4枚・2MB/枚
- **Tumblr**: `POST /v2/blog/{blog_identifier}/posts`（NPF: Neue Post Format）でテキストブロック＋画像ブロック。テキスト緩め、画像10枚
- **Blogger**: Blogger API v3に画像アップロード口がないため、APIで非公開の一時下書きを作り、専用Chromeから内部画像ストアへ画像をアップロードする。取得した `blogger.googleusercontent.com` URLを本文HTMLへ埋め込んで `posts.insert` し、一時下書きはAPIで削除する。**タイトル必須**なので title_rules の導出タイトルを使う（本文の改行は `<br>`/`<p>` へ）
- **X**: OAuth1.0a 署名付き `POST /2/media/upload` で画像 → `POST /2/tweets` に `media.media_ids`。`media_category=tweet_image` 必須。テキスト上限 280、画像4枚・約5MB/枚

各ポスターはFedibirdと同様、非2xxで `RuntimeError`（ステータス＋本文先頭200字）、成功時に投稿URL/idを返す。テストはinjected transport lambdaで実ネットワークなし。

## 5. 共通の追加（lib）

- **`lib/text_limit.rb`**: grapheme 単位で「上限-1字＋『…』」に切り詰め（Q4-a）。上限は SNS 別テーブル（x=280, bluesky=300, tumblr/blogger=なし）。絵文字で崩れないよう grapheme 単位
- **`Media` にサイズ上限フィルタ追加**: SNS 別のバイト上限（bluesky=2MB, x≈5MB, 他緩め）を超える画像を除外（Q5-a）。除外した旨をログに出す。投稿は残りで続行（依存追加なし・stdlib 維持）
- **`lib/oauth_refresh.rb`**: refresh token 更新の共通HTTP処理。Blogger は access token 取得、Tumblr はローテーション応答全体の取得に使用
- **`lib/token_store.rb` / `lib/tumblr_token.rb`**: Tumblr の access token とローテーション後の refresh token を原子的に永続化
- **`lib/oauth1.rb`**: X 用 OAuth1.0a HMAC-SHA1 署名と Authorization ヘッダ生成
- **`config.sample.yml`** に4ブロック追記、**`SETUP.md`** に各トークンの取得先（開発者コンソールの場所・必要スコープ）を追記

## 6. テスト

- **単体テスト（injected transport lambda、実ネットワークなし）**: 各ポスターについてリクエスト組み立て、テキスト上限、画像サイズ、OAuth1署名、Blogger/Tumblr refresh を検証
- **実投稿確認**: Fedibird / Bluesky / Tumblr / Blogger はライブ投稿成功。X は OAuth1.0a 認証通過後に 402 `credits depleted` となり、課金せずライブ投稿は行わない
- dry_runは全ポスターで末端まで伝播（`Poster::Base` の仕組みを利用）

## 7. 当時のスコープ外

- 対話型 OAuth の内蔵（Q2-b。初回トークン取得は外部）
- 画像の縮小・再圧縮（当初は超過画像を落とす方針。その後Bluesky向け縮小を実装）
- ブラウザ投稿先（その後mixi / mixi2 / Jotterを実装）
- X APIの課金判断（2026-08-04に「購入しない」と確定。その後、公式ルール上ブラウザ自動化もしない方針とした）
- 本文が長い時の「リンク付き続き」方式（Q4-b。まず単純切り詰め）

## 8. リスク・留意

- **X の課金**: Pay Per Use のクレジットは購入しない。OAuth1.0a実装は保管し、公式ルール上ブラウザ自動化も行わない
- **Tumblr の token rotation**: 最新 refresh token は `state/tumblr_token.json` にしかない場合がある。失った場合はOAuth認可をやり直す
- **Blogger の画像**: 内部画像ストアへのブラウザアップロードを既存API投稿へ接続済み。画像URLキャッシュと未削除の一時下書きIDを原子的に保存し、次回画像投稿時に回収する。画像付き実投稿を継続確認済み

## 9. 実装結果

- Bluesky: 実装・画像付き実投稿完了。サイズ超過画像は上限内へ縮小する
- Tumblr: NPF multipart のバイナリ安全化、レスポンス形式修正、トークン自動更新まで完了
- Blogger: OAuth refresh、HTML本文、内部画像ストアとの混合方式を実装し、画像付き実投稿を確認済み
- X: OAuth1.0a、v2メディアアップロード、ツイート生成まで完成し認証通過。API課金は行わず、公式ルール上ブラウザ自動化もしない
- Fedibird の写真付き投稿から Blogger / Bluesky への一気通貫を実画像で確認済み
