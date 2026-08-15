# sns-multipost

きっかけ投稿（Fedibird [@hs9587](https://fedibird.com/@hs9587)）を検出し、
同一内容を複数の SNS へ自動投稿する Ruby 製ツール。

旧 [SNS_multi_post](https://github.com/hs9587/SNS_multi_post)（Ruby+Selenium 世代）の後継として、
「トリガ → ファイルキュー → 投稿実行」を分離した構成で作り直している。

## 主な要件

- 入口は Fedibird。きっかけ投稿がそのまま Fedibird 投稿を兼ねる
- 本文と手書きハッシュタグはそのまま展開する
- 画像は先頭から各 SNS の枚数・サイズ上限に合わせる
- 1 ジョブを「1 SNS × 1 投稿」とし、成功は `done/`、失敗は `failed/` に残す
- Bloggerなどタイトル欄のある投稿先には、本文から辞書でタイトルを導出する
- 認証情報とブラウザ状態は Git に入れない
- 基本実装は Ruby。ブラウザ操作ライブラリは対象サービスごとの実証結果で決める

## 現在の状態（2026-08-15）

- Fedibird監視、ファイルキュー、投稿実行、失敗ジョブの再試行からなる基盤は実装・運用確認済み
- Fedibird / Bluesky / Tumblr / Threads はAPIによる実投稿を確認済み
- Bloggerは本文のAPI投稿と、専用Chromeによる内部画像ストア保存を組み合わせた画像付き実投稿を確認済み
- mixi2ポスト、mixiつぶやき、Jotter.me公開テキスト／単画像投稿は専用Chromeによる実投稿を確認済み
- Jotter.meは専用Browser IDの継続、DEN残高読取り、手動振替の画面保持、未検証DENの検証要求を確認済み
- Threadsはテキストと単画像を実投稿確認済み。複数画像を1件にまとめる投稿は実装・自動テスト済みだが、実投稿は未確認
- Tumblrの短命トークンとローテーション型refresh tokenは自動更新・永続化済み
- Windowsタスクスケジューラによる `watch` → `run_queue` の定期実行は稼働実績あり
- タイトル導出は、辞書に一致しない場合も先頭範囲内の句読点・空白で自然に切る
- XはOAuth 1.0a認証まで確認済み。API課金は行わず、Web画面の自動操作も公式ルール上行わない

テストは `bundle exec rake test` で実行する。

## 投稿先

| SNS | 状態 | 手段・留意点 |
|-----|------|--------------|
| Fedibird | 稼働 | API。きっかけ投稿兼用。手動投入時は投稿先にもなる |
| Bluesky | 稼働 | AT Protocol。画像対応 |
| Tumblr | 稼働 | OAuth2 API。トークン自動更新、画像対応 |
| Threads | 稼働・画像運用は再検討 | 公式API。テキストと単画像は実投稿確認済み。複数画像投稿は自動テスト済み |
| Blogger | 稼働 | 混合方式。本文はGoogle OAuth2 API、画像だけ専用ChromeでBlogger内部ストアへ保存 |
| mixi | 稼働 | 専用Chrome。つぶやき、本文150文字・画像1枚 |
| mixi2 | 稼働 | 専用Chrome。本文150文字・画像4枚 |
| Jotter.me | 稼働 | 専用Chrome。公開テキストと先頭画像1枚。画像はBrowser IDと利用可能DENを事前確認 |
| X | APIコード保管・自動投稿保留 | APIは課金せず、公式ルールが禁じるWeb画面の自動操作も行わない |
| Instagram | 手動引き渡し予定 | 非公開個人アカウントを維持。プロアカウント化とブラウザ自動化は行わない |
| Facebook | 手動引き渡し予定 | 個人プロフィールは公式投稿APIの対象外。ブラウザ自動化は行わない |

## 使い方

全コマンドで `-h` / `--help` を利用できる。オプション、引数、実投稿に関する注意は
各コマンドのヘルプで確認する。

    ruby bin/watch --help
    ruby bin/post --help
    ruby bin/run_queue --help

典型的な使い方は次の3通り。

1. `targets.post` の投稿先へ「おはようございます」を投稿する

       ruby bin/post
       ruby bin/run_queue

2. `targets.post` のうちローカル画像対応の投稿先へ、本文と画像を投稿する

       ruby bin/post --image photo.jpg "本文"
       ruby bin/run_queue

3. Fedibirdの新着を検出し、`targets.watch` の投稿先へ展開する

       ruby bin/watch
       ruby bin/run_queue

3番目はWindowsタスクスケジューラで定期実行できる。常時稼働の設定は [SETUP.md](SETUP.md) を参照。

投稿先の限定、監視基準の調整、失敗ジョブの再試行などは各コマンドのヘルプで確認する。

    ruby bin/post --target jotter "本文"
    ruby bin/watch --sync-only
    ruby bin/watch --rewind 1
    ruby bin/retry failed/x.json
    ruby bin/dryrun_titles 200
    ruby bin/threads_auth --help
    ruby bin/browser_login blogger
    ruby bin/mixi_smoke
    ruby bin/mixi2_smoke
    ruby bin/jotter_smoke
    ruby bin/jotter_wallet_smoke
    ruby bin/jotter_wallet_hold
    ruby bin/jotter_wallet_verify
    ruby bin/whoami

設定構造は `config.sample.yml` を参照し、実際の秘密値は Git 管理外の `config.yml` に利用者本人が記入する。
投稿先は `targets.watch`（Fedibird新着からの展開）と `targets.post`（`bin/post` の手動投入）へ
別々に列挙するため、入口ごとに投稿先を選べる。
`bin/post` からFedibirdへ投稿した場合は、成功した投稿IDを `state/self_posted.txt` に記録する。
次の `watch` はその投稿を自己投稿として除外し、他SNSへ重複展開せずに監視基準だけ先へ進める。
デバッグや再処理では `bin/watch --rewind 1` で監視基準だけを1件戻し、次の通常 `bin/watch` で
直近投稿を再検出できる。巻き戻し操作自体はキュー作成・画像取得・投稿を行わず、通常の除外規則は維持する。
したがって `bin/post` 由来の自己投稿や返信は、巻き戻しても再配信されない。失敗ジョブの再実行には
監視基準を戻さず `bin/retry` を使う。

ローカル画像を投稿可能な全投稿先へ手動展開する場合、`--image` は `targets.post` のうち
Fedibird / Bluesky / Tumblr / Blogger / mixi / mixi2 / Jotterのジョブを作る。
ThreadsはMetaが取得できる公開画像URLを必要とするため、
Fedibird投稿後に `--from-fedibird-latest` でThreadsジョブを追加する。

    ruby bin/post --image photo.jpg "本文"
    ruby bin/run_queue
    ruby bin/post --target threads --from-fedibird-latest
    ruby bin/run_queue

`--from-fedibird-latest` は選択したFedibird投稿URLと画像枚数を表示し、最新投稿に画像がなければ
ジョブを作らない。Bloggerを明示的に選んだ場合はFedibird画像を一度ローカルへ取得し、専用Chromeで
`blogger.googleusercontent.com` へ保存してから本文へ埋め込む。
Threadsは投稿時にMetaが公開URLから画像を取得する。2026-08-11にこの経路でThreadsと
Bloggerの単画像投稿を実地確認した。Instagramからの本来の
波及方法を決めた後に、Threads画像の実運用経路は再検討する。

Jotterは複数画像を指定しても先頭1枚だけを使う。画像選択後に画面が示す必要DENを読み、
利用可能DENが足りる場合だけ投稿する。利用可能分が時間経過で未検証へ戻ることがあるため、
画像投稿開始時に利用可能額が90 DEN未満で、未検証分を含めれば足りる場合は自動で検証要求する。
別ブラウザから専用Chromeへまとめて振り替える場合は `jotter_wallet_hold`、明示的に検証する場合は
`jotter_wallet_verify` を使う。詳細は
[Jotter画像投稿とDEN運用](docs/specs/2026-08-15-jotter-image-den.md) を参照。
`dry_run: true` でもキューは `done/` へ移るため、本番投稿用ジョブの事前確認には使わないこと。

## ロードマップ

1. ページング、HTTPタイムアウト、排他制御、古いジョブ・画像の清掃など、安全性と安定性を高める
2. Threads画像の実運用経路と、複数画像投稿の実地確認を再検討する
3. X / Instagram / Facebook向け手動引き渡しを含む残件の順番を再検討する

従来のBlogger公開記事では画像URLが公開後も `s3.fedibird.com` のままで、Blogger側へ自動複製
されなかった。このため、現在はBlogger API投稿の前に専用Chromeで内部画像ストアへ保存する。
Instagram連携とThreads画像の実運用経路は今後再検討する。

Blogger編集画面の「パソコンからアップロード」を自動操作する小規模実証では、ローカルPNGを
`blogger.googleusercontent.com` へ保存し、Chromeを閉じた後も下書きで表示できた。
表示用URLの `/s320/` を `/s0/` に変更した元サイズURLも、認証なしでHTTP 200を確認した。
詳細と再現手順は `docs/specs/2026-08-11-blogger-image-store.md` を参照。

通常投稿ではAPIで非公開の一時下書きを作り、画像URL取得後にその下書きをAPIで削除する。
取得済みURLは `state/blogger_image_store.json` に保存し、再試行時の重複アップロードを抑える。
画像付き投稿の前に一度 `ruby bin/browser_login blogger` を実行して専用Chromeへログインしておく。

## 保存容量と清掃

ブラウザ投稿の失敗時は、原因調査用に表示中の画面を `failed/<ジョブ名>.png` へ保存する。
成功時には保存せず、スクリーンショット、ジョブ、画像、ChromeプロファイルはいずれもGit管理外とする。

開発中は機能の節目に `queue/`、`done/`、`failed/`、`state/media/`、`state/browser/`、`logs/` の
ファイル数と容量を確認する。実稼働後は増加傾向を見て保持日数と容量上限を決め、古い成功ジョブ、
参照されなくなった画像、失敗スクリーンショット、Chromeキャッシュの順にローテーションを検討する。
失敗ジョブ本体は、再実行や原因調査が済むまで自動削除しない。

設計の原点は [docs/specs/2026-07-19-sns-multipost-design.md](docs/specs/2026-07-19-sns-multipost-design.md)、
API投稿先の実装記録は [docs/specs/2026-07-20-sns-multipost-phase2-design.md](docs/specs/2026-07-20-sns-multipost-phase2-design.md)、
Threads APIは [docs/specs/2026-08-06-threads-api.md](docs/specs/2026-08-06-threads-api.md)、
ブラウザ投稿先の調査状況は [docs/specs/2026-08-09-phase3-browser.md](docs/specs/2026-08-09-phase3-browser.md)、
Jotter画像とDEN運用は [docs/specs/2026-08-15-jotter-image-den.md](docs/specs/2026-08-15-jotter-image-den.md)、
トークン取得と常駐運用は [SETUP.md](SETUP.md) を参照。
