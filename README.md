# sns-multipost

きっかけ投稿（Fedibird [@hs9587](https://fedibird.com/@hs9587)）を検出し、
同一内容を複数の SNS へ自動投稿する Ruby 製ツール。

旧 [SNS_multi_post](https://github.com/hs9587/SNS_multi_post)（Ruby+Selenium 世代）の後継として、
「トリガ → ファイルキュー → 投稿実行」を分離した構成で作り直している。

## 現在の状態（2026-08-04）

- Phase 1（基盤＋Fedibird）と Phase 2（API 組）は実装完了
- Fedibird / Bluesky / Tumblr / Blogger は実投稿確認済み
- X は OAuth1.0a 認証まで確認済み。API課金は行わず、Phase 3でブラウザ投稿を実装する
- Tumblr の短命トークンとローテーション型 refresh token は自動更新・永続化済み
- Fedibird 監視から Blogger / Bluesky への写真付き投稿を一気通貫で確認済み
- Windows タスクスケジューラによる定期実行は稼働実績あり
- 次の実装対象はタイトル導出の句読点対応、その後 Jotter のテキスト投稿

テストは `bundle exec rake test` で実行する。

## 投稿先

| SNS | 状態 | 手段・留意点 |
|-----|------|--------------|
| Fedibird | 稼働 | きっかけ投稿兼用。手動投入時は投稿先にもなる |
| Bluesky | 稼働 | AT Protocol。画像対応 |
| Tumblr | 稼働 | OAuth2。トークン自動更新、画像対応 |
| Blogger | 稼働 | Google OAuth2。画像は現在 Fedibird の画像 URL をホットリンク |
| X | APIコード完成・ブラウザ未実装 | APIは課金せず、Phase 3でログイン済みブラウザから投稿する |
| Instagram | 未実装 | Phase 3 のブラウザ組。画像付き投稿のハブ候補 |
| mixi / mixi2 | 未実装 | Phase 3 のブラウザ組。mixi2 は Web 投稿可否の調査が必要 |
| Jotter.me | 調査中 | 初期版はテキストのみ。ブラウザ操作スパイクを進行中 |
| Facebook / Threads | バックログ | 写真なし投稿を補う直接テキスト投稿経路を検討 |

## 主な要件

- 入口は Fedibird。きっかけ投稿がそのまま Fedibird 投稿を兼ねる
- 本文と手書きハッシュタグはそのまま展開する
- 画像は先頭から各 SNS の枚数・サイズ上限に合わせる
- 1 ジョブを「1 SNS × 1 投稿」とし、成功は `done/`、失敗は `failed/` に残す
- Blogger や mixi 日記などタイトル欄のある投稿先には、本文から辞書でタイトルを導出する
- 認証情報とブラウザ状態は Git に入れない
- 基本実装は Ruby。ブラウザ操作ライブラリは対象サービスごとの実証結果で決める

## 使い方

    ruby bin/post "本文"          # 手動投稿（対象 SNS のキューを生成）
    ruby bin/run_queue            # キュー処理。dry_run=false なら実投稿
    ruby bin/watch                # Fedibird 新着検出 → キュー生成
    ruby bin/watch --sync-only    # キューを作らず since_id だけ最新へ進める
    ruby bin/retry failed/x.json  # 失敗ジョブを再実行
    ruby bin/dryrun_titles 200    # タイトル辞書のドライラン
    ruby bin/whoami               # Fedibird の account_id 確認

設定構造は `config.sample.yml` を参照し、実際の秘密値は Git 管理外の `config.yml` に利用者本人が記入する。
`dry_run: true` でもキューは `done/` へ移るため、本番投稿用ジョブの事前確認には使わないこと。

## ロードマップ

1. タイトルのフォールバックを、先頭範囲内の句読点で自然に切る
2. Jotter のログイン完了判定と投稿画面への遷移を確定し、テキストポスターを実装
3. X / Instagram / mixi / mixi2 のブラウザポスターを実装
4. Facebook / Threads の直接テキスト投稿を追加
5. Blogger の画像を恒久的な画像ホストへ移行
6. ページング、HTTP タイムアウト、排他制御、古いジョブ・画像の清掃を追加

設計の原点は [docs/specs/2026-07-19-sns-multipost-design.md](docs/specs/2026-07-19-sns-multipost-design.md)、
Phase 2 の実装結果は [docs/specs/2026-07-20-sns-multipost-phase2-design.md](docs/specs/2026-07-20-sns-multipost-phase2-design.md)、
トークン取得と常駐運用は [SETUP.md](SETUP.md) を参照。
