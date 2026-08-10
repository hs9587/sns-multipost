# Threads API テキスト・画像投稿

- 日付: 2026-08-06
- 状態: テキストは実投稿確認完了（2026-08-08）。画像は実装・自動テストのみで、実地テスト未実施（2026-08-11）
- 対象入口: 現在はテキストの `targets.post` のみ。画像経路は方針決定まで有効にしない

## 方針

Threads はブラウザ操作ではなく、Meta公式 Threads API を使う。
テキスト投稿は `POST https://graph.threads.net/me/threads` に
`media_type=TEXT` と `auto_publish_text=true` を指定して公開する。

画像はローカルファイルをAPIへアップロードせず、Metaから取得可能な公開 `image_url` が必要になる。
実装上はジョブの `media_urls` を使い、画像1枚ではIMAGEコンテナを作成、2～20枚では
画像ごとの子コンテナとCAROUSELコンテナを作成する。各コンテナの状態が `FINISHED` になるまで待ち、
`POST /me/threads_publish` で公開する。`ERROR` または `EXPIRED` は失敗ジョブとして残す。

認証スコープは `threads_basic,threads_content_publish`。`bin/threads_auth` が
認可URL生成、認可コード交換、短期トークンから長期トークンへの交換を行い、
`state/threads_token.json` に保存する。長期トークンは期限の7日前から更新する。

## 実装

- `lib/threads_api.rb`: テキスト、単画像、画像カルーセル投稿HTTPクライアントとコンテナ状態確認
- `lib/threads_oauth.rb`: 認可URL、コード交換、長期化、更新
- `lib/threads_token.rb`: 保存トークンの選択と期限前更新
- `lib/poster/threads.rb`: 500 graphemeへの切り詰め、画像URL選択、ポスター登録
- `bin/threads_auth`: 初回OAuthの2段階補助

Threadsの初期画像対応は静止画のみとし、動画は対象外とする。Facebook個人プロフィールは
公式投稿APIの対象外で、ブラウザ自動化も行わないため、将来の手動引き渡し候補として扱う。

## 実投稿確認

`bin/post` で作成した Threads 向けジョブを `bin/run_queue` で処理し、
APIが投稿IDを返すことと、Threads上に投稿が公開されたことを確認済み。
実際の投稿IDや認証情報は文書・Gitには保存しない。

画像投稿は自動テストで、単画像の作成・処理待ち・公開、および複数画像の子コンテナ・
カルーセル作成・処理待ち・公開まで確認済み。ただし、実運用ではInstagramからThreadsへの波及を
想定しており、APIが必要とする恒久的な公開画像URLも未決定である。このため画像付き実地テストは
意図的に行っていない。恒久画像置き場とInstagram連携を決めた後に、API画像投稿を使うかも含めて再検討する。

公式資料:

- Threads API: https://www.postman.com/meta/threads/documentation/dht3nzz/threads-api
- 単画像コンテナ: https://www.postman.com/meta/threads/request/34203612-c5844b32-22e8-4c0c-9564-2694cede8304
- カルーセルコンテナ: https://www.postman.com/meta/threads/request/34203612-b0861a47-db0e-4940-a692-2304669603b3
- コンテナ状態確認: https://www.postman.com/meta/threads/request/34203612-72c20362-5b0c-4f14-b9cd-4315ff91cd85
