# sns-multipost

きっかけ投稿（Fedibird [@hs9587](https://fedibird.com/@hs9587)）を検出し、
同一内容を複数の SNS へ自動投稿する Ruby 製ツール。

旧 [SNS_multi_post](https://github.com/hs9587/SNS_multi_post)（Ruby+Selenium 世代）の後継として、
「トリガ → ファイルキュー → 投稿実行」を分離した構成で作り直している。

## 現在の状態（2026-08-11）

- Phase 1（基盤＋Fedibird）と Phase 2（API 組）は実装完了
- Fedibird / Bluesky / Tumblr / Blogger / Threads は実投稿確認済み
- X は OAuth1.0a 認証まで確認済み。API課金は行わず、Web画面の自動操作も公式ルール上行わない
- Threads は公式APIによるテキスト投稿と、Fedibird最新画像URLを使う単画像投稿を実地確認済み。カルーセルは自動テスト済み
- Tumblr の短命トークンとローテーション型 refresh token は自動更新・永続化済み
- Fedibird 監視から Blogger / Bluesky への写真付き投稿を一気通貫で確認済み
- Windows タスクスケジューラによる定期実行は稼働実績あり
- タイトル導出は、辞書に一致しない場合も先頭範囲内の句読点・空白で自然に切る
- Phase 3はmixi2ポスト、mixiつぶやき、Jotter.me公開テキスト投稿を実投稿確認済み

テストは `bundle exec rake test` で実行する。

## 投稿先

| SNS | 状態 | 手段・留意点 |
|-----|------|--------------|
| Fedibird | 稼働 | きっかけ投稿兼用。手動投入時は投稿先にもなる |
| Bluesky | 稼働 | AT Protocol。画像対応 |
| Tumblr | 稼働 | OAuth2。トークン自動更新、画像対応 |
| Blogger | 稼働 | Google OAuth2。公開後の記事本文も Fedibird の画像 URL をホットリンク |
| X | APIコード保管・自動投稿保留 | APIは課金せず、公式ルールが禁じるWeb画面の自動操作も行わない |
| Instagram | 手動引き渡し予定 | 既存の非公開個人アカウントを維持。プロアカウント化とブラウザ自動化は行わない |
| mixi | 稼働 | 専用Chromeからつぶやき実投稿確認済み。本文150文字・画像1枚 |
| mixi2 | 稼働 | 専用Chromeから実投稿確認済み。本文150文字・画像4枚 |
| Jotter.me | 稼働 | セーブポイントを素のChromeで復元後に自動操作を接続。公開テキスト投稿・URL確認済み |
| Threads | 稼働・画像運用は再検討 | テキストと単画像を実投稿確認済み。カルーセルは自動テスト済み。Instagramからの波及方法は今後検討 |
| Facebook | 手動引き渡し予定 | 個人プロフィールは公式投稿APIの対象外。ブラウザ自動化は行わない |

## 主な要件

- 入口は Fedibird。きっかけ投稿がそのまま Fedibird 投稿を兼ねる
- 本文と手書きハッシュタグはそのまま展開する
- 画像は先頭から各 SNS の枚数・サイズ上限に合わせる
- 1 ジョブを「1 SNS × 1 投稿」とし、成功は `done/`、失敗は `failed/` に残す
- Bloggerなどタイトル欄のある投稿先には、本文から辞書でタイトルを導出する
- 認証情報とブラウザ状態は Git に入れない
- 基本実装は Ruby。ブラウザ操作ライブラリは対象サービスごとの実証結果で決める

## 使い方

    ruby bin/post                 # 「おはようございます」で手動投稿キューを生成
    ruby bin/post "本文"          # 任意の本文で手動投稿キューを生成
    ruby bin/post --target jotter "本文" # 指定した1 SNSだけのキューを生成
    ruby bin/post --image photo.jpg "本文" # ローカル画像対応5 SNSの画像付きキューを生成
    ruby bin/post --target fedibird --image photo.jpg "本文"
    ruby bin/post --target bluesky --image one.jpg --image two.jpg "本文"
    ruby bin/post --target threads --target blogger --from-fedibird-latest
    ruby bin/run_queue            # キュー処理。dry_run=false なら実投稿
    ruby bin/watch                # Fedibird 新着検出 → キュー生成
    ruby bin/watch --sync-only    # キューを作らず since_id だけ最新へ進める
    ruby bin/watch --rewind 1     # キューを作らず監視基準を1件戻す
    ruby bin/retry failed/x.json  # 失敗ジョブを再実行
    ruby bin/dryrun_titles 200    # タイトル辞書のドライラン
    ruby bin/threads_auth --help  # Threads API の初回OAuth認証
    ruby bin/browser_login mixi   # mixiブラウザ投稿専用Chromeで初回ログイン
    ruby bin/mixi_smoke           # 投稿せずmixiログインとつぶやきフォームを確認
    ruby bin/browser_login mixi2  # ブラウザ投稿専用Chromeで初回ログイン
    ruby bin/mixi2_smoke          # 投稿せずmixi2ログインと投稿画面を確認
    ruby bin/jotter_smoke         # 投稿せずJotterログイン、本人、投稿フォーム、公開範囲を確認
    ruby bin/whoami               # Fedibird の account_id 確認

全コマンドで `-h` / `--help` を利用できる。オプション、引数、実投稿に関する注意は
各コマンドのヘルプで確認する。

    ruby bin/watch --help
    ruby bin/run_queue --help

設定構造は `config.sample.yml` を参照し、実際の秘密値は Git 管理外の `config.yml` に利用者本人が記入する。
投稿先は `targets.watch`（Fedibird新着からの展開）と `targets.post`（`bin/post` の手動投入）へ
別々に列挙するため、入口ごとに投稿先を選べる。
`bin/post` からFedibirdへ投稿した場合は、成功した投稿IDを `state/self_posted.txt` に記録する。
次の `watch` はその投稿を自己投稿として除外し、他SNSへ重複展開せずに監視基準だけ先へ進める。
デバッグや再処理では `bin/watch --rewind 1` で監視基準だけを1件戻し、次の通常 `bin/watch` で
直近投稿を再検出できる。巻き戻し操作自体はキュー作成・画像取得・投稿を行わず、通常の除外規則は維持する。
したがって `bin/post` 由来の自己投稿や返信は、巻き戻しても再配信されない。失敗ジョブの再実行には
監視基準を戻さず `bin/retry` を使う。

ローカル画像を投稿可能な全投稿先へ手動展開する場合は、処理を2段階に分ける。最初の `--image` は
Fedibird / Bluesky / Tumblr / mixi / mixi2だけのジョブを作り、1回目の `run_queue` でFedibirdにも
公開画像を作る。その後 `--from-fedibird-latest` が自分の最新Fedibird投稿から本文と画像URLを読み、
Threads / Bloggerだけのジョブを作る。

    ruby bin/post --image photo.jpg "本文"
    ruby bin/run_queue
    ruby bin/post --target threads --target blogger --from-fedibird-latest
    ruby bin/run_queue

`--from-fedibird-latest` は選択したFedibird投稿URLと画像枚数を表示し、最新投稿に画像がなければ
ジョブを作らない。BloggerはFedibird画像を継続的にホットリンクするため、恒久画像置き場の課題は残る。
Threadsは投稿時にMetaが公開URLから画像を取得する。2026-08-11にこの二段階経路でThreadsと
Bloggerの単画像投稿を実地確認し、公開確認後にテスト投稿を削除した。Instagramからの本来の
波及方法を決めた後に、Threads画像の実運用経路は再検討する。
`dry_run: true` でもキューは `done/` へ移るため、本番投稿用ジョブの事前確認には使わないこと。

## ロードマップ

1. Bloggerの恒久画像置き場と、InstagramからThreadsへの波及方法を検討
2. ページング、HTTPタイムアウト、排他制御、古いジョブ・画像の清掃のうち導入しやすいものを追加
3. ここまでで、X / Instagram / Facebook向け手動引き渡しを含む残件の順番を再検討

Bloggerの公開済み記事を確認したところ、記事本文の画像URLは公開後も `s3.fedibird.com` のままで、
Blogger側へ自動的に複製されてはいなかった。Threads画像APIもMeta側から取得できる公開URLを必要とする。
Fedibird最新画像を使うThreads単画像投稿は成功したが、Bloggerは画像をホットリンクし続ける。
恒久画像置き場とInstagram連携の方針を決めた後に、両投稿先の実運用経路を再検討する。

## 保存容量と清掃

ブラウザ投稿の失敗時は、原因調査用に表示中の画面を `failed/<ジョブ名>.png` へ保存する。
成功時には保存せず、スクリーンショット、ジョブ、画像、ChromeプロファイルはいずれもGit管理外とする。

開発中は機能の節目に `queue/`、`done/`、`failed/`、`state/media/`、`state/browser/`、`logs/` の
ファイル数と容量を確認する。実稼働後は増加傾向を見て保持日数と容量上限を決め、古い成功ジョブ、
参照されなくなった画像、失敗スクリーンショット、Chromeキャッシュの順にローテーションを検討する。
失敗ジョブ本体は、再実行や原因調査が済むまで自動削除しない。

設計の原点は [docs/specs/2026-07-19-sns-multipost-design.md](docs/specs/2026-07-19-sns-multipost-design.md)、
Phase 2 の実装結果は [docs/specs/2026-07-20-sns-multipost-phase2-design.md](docs/specs/2026-07-20-sns-multipost-phase2-design.md)、
Threads APIは [docs/specs/2026-08-06-threads-api.md](docs/specs/2026-08-06-threads-api.md)、
Phase 3の調査状況は [docs/specs/2026-08-09-phase3-browser.md](docs/specs/2026-08-09-phase3-browser.md)、
トークン取得と常駐運用は [SETUP.md](SETUP.md) を参照。
