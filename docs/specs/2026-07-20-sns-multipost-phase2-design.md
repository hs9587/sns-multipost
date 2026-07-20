# sns-multipost Phase 2 設計ドキュメント（API組ポスター）

- 日付: 2026-07-20
- 状態: ユーザー承認済み設計
- 前提: Phase 1 完了（`Poster::Base` パターン・ファイルキュー・injected transport・config.yml 確立済み）
- リポジトリ: GitHub `hs9587/sns-multipost`（既存 main に追加）

## 1. 目的

Phase 1 で確立した基盤の上に、API で投稿できる4 SNS のポスターを追加する。動機は Phase 1 と同じ（MT変換機の開発データ作成 =「いろんな SNS に投稿している状態」を作る）。

## 2. スコープと順序

API組4ポスターを**認証の軽い順に1本ずつ**追加する。各ポスター = 1タスク（実装 → 単体テスト → commit/push、実投稿確認は最後にまとめて）:

**Bluesky → Tumblr → Blogger → X**

各ポスターは `Poster::Base` を継承し `Poster.register("<sns>", 自クラス)` で登録する。`bin/run_queue` はレジストリ経由なので登録するだけで処理対象になる。`lib/poster/all.rb` に require を追記する。

## 3. 認証

すべて `config.yml` に値を置き、Claude は値を見ない（Phase 1 と同じ流儀）。トークンの初回取得は外部（各開発者コンソール等）で行う。

| SNS | 認証 | config.yml のキー |
|-----|------|------------------|
| Bluesky | アプリパスワードで `com.atproto.server.createSession` → accessJwt | `handle`, `app_password` |
| Tumblr | OAuth2 Bearer | `access_token`, `blog_identifier` |
| Blogger | Google OAuth2（refresh 運用） | `client_id`, `client_secret`, `refresh_token`, `blog_id` |
| X | OAuth2 Bearer（refresh 運用） | `client_id`, `client_secret`, `refresh_token` |

Blogger と X はアクセストークンが短命なので、**refresh token でアクセストークンを更新する処理**をツールが持つ（`lib/oauth_refresh.rb` に共通化）。対話型 OAuth の内蔵はしない。初回 refresh token 取得を楽にする `bin/get_refresh_token` は必要になれば後付け（Q2-c）。

## 4. 各ポスターの投稿と画像

画像入りで実装する。画像元は Phase 1 の watch がダウンロードしたローカルファイル（ジョブの `media_paths`）。`Media.for_sns` で SNS 別の枚数上限に切り詰め済みのものを使う。

- **Bluesky**: `com.atproto.repo.uploadBlob` で画像を上げ、`app.bsky.feed.post` レコードに embed（images）。テキスト上限 300 grapheme、画像4枚・約1MB/枚
- **Tumblr**: `POST /v2/blog/{blog_identifier}/posts`（NPF: Neue Post Format）でテキストブロック＋画像ブロック。テキスト緩め、画像10枚
- **Blogger**: 2段構え。画像を先にアップロードして googleusercontent URL を取得 → 本文 HTML に `<img>` で埋め込み → `posts.insert`。**タイトル必須**なので title_rules の導出タイトルを使う（本文の改行は `<br>`/`<p>` へ）
- **X**: `media/upload` で画像 → `POST /2/tweets` に `media.media_ids`。テキスト上限 280、画像4枚・約5MB/枚

各ポスターは Phase 1 の Fedibird 同様、非2xx で `RuntimeError`（ステータス＋本文先頭200字）、成功時に投稿 URL/id を返す。テストは injected transport lambda で実ネットワークなし。

## 5. 共通の追加（lib）

- **`lib/text_limit.rb`**: grapheme 単位で「上限-1字＋『…』」に切り詰め（Q4-a）。上限は SNS 別テーブル（x=280, bluesky=300, tumblr/blogger=なし）。絵文字で崩れないよう grapheme 単位
- **`Media` にサイズ上限フィルタ追加**: SNS 別のバイト上限（bluesky≈1MB, x≈5MB, 他緩め）を超える画像を除外（Q5-a）。除外した旨をログに出す。投稿は残りで続行（依存追加なし・stdlib 維持）
- **`lib/oauth_refresh.rb`**: refresh token → access token 更新の共通処理（Blogger/X）。token エンドポイント・client 資格情報を受け、新しいアクセストークンを返す
- **`config.sample.yml`** に4ブロック追記、**`SETUP.md`** に各トークンの取得先（開発者コンソールの場所・必要スコープ）を追記

## 6. テスト

- **単体テスト（injected transport lambda、実ネットワークなし）**: 各ポスターについてリクエスト組み立て（エンドポイント・ヘッダ・本文/メディアの形）、テキスト上限切り詰め、画像サイズ除外、refresh 発火（Blogger/X）を検証
- **実投稿1回（手動・要ユーザートークン）**: 各 SNS で Phase 1 の Fedibird と同じ流れ（`dry_run:false` → `bin/post` → `bin/run_queue` → ブラウザ確認 → 削除可）。実装・単体テストを全部終えてから最後にまとめて疎通確認する
- dry_run は全ポスターで末端まで伝播（Phase 1 の `Poster::Base` の仕組みをそのまま利用）

## 7. スコープ外（Phase 2 に入れない）

- 対話型 OAuth の内蔵（Q2-b。初回トークン取得は外部）
- 画像の縮小・再圧縮（Q5-b。超過画像は落とすだけ）
- ブラウザ組（Instagram / mixi / mixi2 / Jotter）は Phase 3
- X 無料枠が実運用で厳しい場合の降格・保留判断は、4つ動いた後に実データで判断
- 本文が長い時の「リンク付き続き」方式（Q4-b。まず単純切り詰め）

## 8. リスク・留意

- **X 無料枠**: 投稿数枠・規約が流動的。実装はするが、実運用で枠が厳しければ有効化保留やブラウザ組降格を後から判断（Phase 1 要調査4点の1つ）
- **Tumblr の OAuth 版**: OAuth2 Bearer を前提に書いているが、実運用で OAuth1.0a が必要なら実装フェーズで切替（実装前にユーザー確認）
- **Blogger の画像アップロード API**: `posts.insert` に画像口が無いため別アップロード経路を使う。この経路の具体（エンドポイント）は実装タスクの最初に小さく検証する
