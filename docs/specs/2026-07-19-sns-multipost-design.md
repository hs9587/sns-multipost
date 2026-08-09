# sns-multipost 設計ドキュメント

- 日付: 2026-07-19
- 状態: ユーザー承認済み設計。Phase 1・2 実装完了、Phase 3 調査着手（2026-08-09 現在）
- リポジトリ: GitHub `hs9587/sns-multipost`（パブリック・新規作成）

## 1. 目的と背景

きっかけ投稿（Fedibird @hs9587）を検出し、同一内容を複数 SNS へ自動投稿する。
動機は MT変換機の開発データ作成 —「いろんな SNS に投稿している状態」を作る。

旧 `hs9587/SNS_multi_post`（Ruby+Selenium+Edge、cookie 移植方式、現在は動かない）の**後継**として全面的に作り直す。旧リポジトリはアーカイブ扱いで残す。新 README の冒頭に「旧 SNS_multi_post の後継として作り直したもの」である旨と旧リポジトリへのリンクを置く。

## 2. 決定事項サマリ

| 項目 | 決定 |
|------|------|
| 実装言語 | 全 Ruby。API 部は stdlib 中心、ブラウザ部はサービスごとのスパイクでドライバを選定 |
| 実行形態 | 非常駐。ファイルキュー、タスクスケジューラ駆動 |
| 投稿先 | X / Instagram / mixi旧 / mixi2 / Bluesky / Blogger / Tumblr / Jotter.me。写真なし投稿向けに Facebook・Threads 直接投稿も追加予定 |
| 入口 | Fedibird（きっかけ投稿自体が Fedibird 投稿を兼ねる） |
| 投稿内容 | きっかけ投稿と同一（ハッシュタグ含め全文）。画像は先頭から各SNS上限まで（mixi=1枚） |
| タイトル | 本文は全SNS同一。タイトル欄のあるSNSのみ辞書で導出（後述） |
| リポジトリ | GitHub hs9587/sns-multipost、パブリック |
| 本番機 | 稼働中の Windows 機。git clone + 手順書で移設可能に |
| 運用方式 | ハイブリッド: スクリプト自動投稿、画面変更で壊れた SNS は Claude が修理 |

## 3. 全体像

```
[トリガ] --(JSONジョブ生成)--> [queue/] --(順次処理)--> [ポスター群] --> 各SNS
   |                                                        |
 タスクスケジューラで数分おき                     成功→done/  失敗→failed/
```

トリガ・キュー・投稿実行を分離する。出先対応など将来の拡張はトリガの差し替えで実現する。

## 4. リポジトリ構成

```
sns-multipost/
  README.md               旧 SNS_multi_post の後継である旨＋リンクを冒頭に
  SETUP.md                移設手順書（clone〜スケジューラ登録〜初回ログイン）
  bin/
    watch                 トリガ1: Fedibird ポーリング → ジョブ生成
    post                  トリガ2: コマンド直接投入（おはよう2way目）
    run_queue             キュー処理（ポスター実行）
    retry                 failed/ のジョブを個別再実行
    dryrun_titles         過去投稿にタイトル辞書を当てて一覧表を出す
  lib/
    poster/               1 SNS = 1 ファイル（x.rb, instagram.rb, mixi.rb, mixi2.rb,
                          bluesky.rb, blogger.rb, tumblr.rb, jotter.rb, fedibird.rb）
    title_rules.rb        タイトル辞書エンジン
    job_queue.rb          ジョブの生成・遷移（queue/ → done/ | failed/）
    media.rb              画像ダウンロード・SNS別枚数切り詰め
  title_rules.yml         タイトル辞書（育てる対象・コミットする）
  config.sample.yml       設定雛形（コミットする）
  config.yml              実設定・秘匿値（.gitignore）
  queue/ done/ failed/    ジョブ置き場（.gitignore、.keep のみコミット）
  state/                  最終処理済み投稿ID、ブラウザプロファイル（.gitignore）
  logs/                   実行ログ（.gitignore）
  test/
```

## 5. トリガ（2系統）

- `bin/watch`: Fedibird API で自分の新着投稿を取得。最終処理済み status id を `state/` に記録して差分検出。新着1投稿につき投稿先SNS数ぶんのジョブを `queue/` に書く。画像はこの時点でダウンロードしてローカルパスをジョブに記録。タスクスケジューラで5分おき起動。
- `bin/post "本文..."`: 写真なし・指示だけの投稿（おはよう投稿の2way目）。この場合きっかけ投稿が存在しないため、**Fedibird を含む全SNS** のジョブを作る。

## 6. ジョブ形式

1ジョブ = 1SNS × 1投稿の JSON ファイル。ファイル名は `20260719-143000_x_a1b2.json`（日時_SNS名_短縮id）。

内容: 対象SNS / 本文 / 導出済みタイトル / 画像ローカルパス配列 / 元投稿URL / 試行回数 / 最終エラー。

タイトル導出は**ジョブ生成時に済ませて JSON に焼き込む**。ポスターは判断せず、失敗ジョブを見れば投稿しようとした内容が全部わかる。

## 7. ポスター

共通インターフェース `Poster::Base#post(job)` を各SNSが実装。

| 組 | SNS | 手段 |
|----|-----|------|
| API組 | Bluesky / Tumblr / Blogger / Fedibird / Threads | 各 REST API（HTTP+JSON、gem は最小限）。Threads は `bin/post` のテキストのみ |
| API組(保管) | X | API v2 + OAuth1.0a のコードと認証確認結果は残すが、クレジット購入予定がないため実運用には使わない |
| ブラウザ組(稼働) | mixi2 | 専用ChromeプロファイルをFerrumで操作。テキスト・画像投稿の実投稿確認済み |
| ブラウザ組(未実装) | Instagram / mixi旧 / Jotter.me / Facebook個人プロフィール | サービスごとのスパイクで操作特性と規約を確認する |

- Xの公式Automation rulesはWebサイトのスクリプト操作を禁じているため、Xをブラウザ自動投稿しない。必要なら本文準備と公式Webを開くところまでの手動引き渡しにする
- Instagram は画像付き投稿のハブ候補。写真なし投稿は Threads API へ直接投稿し、Facebook 個人プロフィールはブラウザ投稿で追加する
- ブラウザ組は失敗時にスクリーンショットを failed/ のジョブ横に保存（Claude 修理の一次資料）
- Jotter.me は **v1 テキスト投稿のみ**。セーブポイント URL を毎回開き、同一ブラウザプロセス内で投稿する。画像投稿には DEN が必要なためスコープ外
- mixi2は専用Chromeプロファイル、Ferrum、最大150文字・画像4枚で実装し、キュー経由の実投稿まで確認済み

### 要調査（実装フェーズ最初に小さく検証）

1. mixi2 のログイン後DOMと投稿完了判定（Web投稿の提供自体は確認済み）
2. Jotter.me の安定したログイン完了判定と「メモを作成します」トリガのセレクタ
3. Instagram は対象アカウントで公式投稿APIを利用できるか
4. Facebook個人プロフィールのブラウザ操作上の安定性と利用条件
5. X APIはクレジットを購入せず、Web画面の自動操作も行わない

## 8. タイトル辞書

タイトル欄のある SNS（Blogger 必須・mixi日記 必須・Tumblr 任意）向けに、`title_rules.yml` を上から順に評価:

1. **おはよう**: 本文に「おはよう」→ タイトル「おはよう」
2. **コーヒー**: コーヒー語彙（コーヒー、珈琲、ホット、アイス、アメリカン、ブレンド、ブリュー、モカ、キリマンジャロ、マンデリン等の産地・銘柄）、または非コーヒー飲料語（ティー、紅茶、ジュース等）が無く飲み物文脈（行きつけ店名リスト等）がある場合コーヒー扱い。タイトルは アイス系語彙→「アイス」、産地・銘柄→その名、他→「ホット」
3. **食べ物リスト**: パン、ブレッド、スパゲティ、そば、ごはん、おにぎり等 → 最初にマッチした語
4. **フォールバック**: 先頭12字以内に句読点または空白文字があれば、その直前まで。無ければ本文冒頭12字＋「…」

辞書は「ドライラン＋指摘」で育てる: `bin/dryrun_titles` が Fedibird 公開 API で過去投稿200〜500件を取得し「投稿→タイトル」一覧表を出力。違和感のある行の指摘を受けて Claude が辞書に規則を追加する。X の過去分はアーカイブ zip の取り込み口を将来追加可能。

## 9. エラー処理・修理運用

- 失敗ジョブは `failed/` に残る（本文・タイトル・画像パス・エラーメッセージ・スクショ付き）
- `bin/retry failed/xxx.json` で単体再実行
- 「mixi が壊れた」→ failed のジョブ＋スクショを Claude に見せ、`lib/poster/mixi.rb` を修理 → retry で確認
- 1ジョブ1SNS なので、1サービスの故障が他SNSのジョブを巻き添えにしない

## 10. テスト

- 単体テスト: タイトル辞書（最重要・回帰しやすい）、ジョブ生成・キュー遷移
- 各ポスターに `dry_run` モード（外部投稿を行わず疑似結果を返す）。処理済みジョブは `done/` へ移る。ブラウザ組はログイン〜投稿画面到達の smoke test
- 本物投稿の確認は各SNS 1回ずつ手動キック

## 11. 秘匿情報の扱い

- `config.yml`（APIキー・トークン・アカウント名等）と `state/`（token store・ブラウザプロファイル）は `.gitignore`。Jotter セーブポイント URL は環境変数などローカル限定の経路で渡す
- `config.sample.yml` を雛形としてコミット。SETUP.md に「何をどこから取得してどの欄に書くか」を記載
- **秘匿値はリポジトリ外**: config.sample.yml を雛形に、利用者本人が config.yml に直接記入する（アカウント名・ユーザーID程度は設計上必要になれば共有可）
- **別マシンへの移行**: APIキー類は本人管理の経路（USB・パスワードマネージャ等、Git 経由にしない）で持ち込み移行先の config.yml に記入。ブラウザログイン状態は**移植せず移行先で別採取**（初回手動ログイン）。機体ごとに独立させ、cookie 移植はしない

## 12. 移設・運用

- 開発: 在宅機 `sns-multipost`。本番: 稼働中の Windows 機（Claude Code 導入済み）
- API 組の移設手順（SETUP.md に記載): git clone → `bundle install` → config.yml 記入 → `bin/watch --sync-only` → schtasks でスケジューラ登録（bin/watch の直後に bin/run_queue）
- ブラウザ組は未実装。完成後、採用ドライバの導入と移設先での初回ログイン手順を追加する

## 13. スコープ外（次ステップ候補）

- Jotter.me の画像投稿（DEN の用意が必要。DEN 残高は送金・振替機能で用意）
- 出先対応のトリガ差し替え（Fedibird 監視の常駐化等）
- タイトル判定の LLM ハイブリッド（c案）
- note への投稿（対象外と決定済み）

## 14. 実装状況と残課題（2026-08-09）

- Phase 1: ファイルキュー、Fedibird 監視・投稿、タイトル辞書、再試行まで完了
- Phase 2: Bluesky / Tumblr / Blogger / X API を実装。X 以外はライブ投稿済み。X API は認証通過後に 402 `credits depleted` を確認。APIコードは保管する
- Tumblr: ローテーション型 refresh token の自動更新と `state/tumblr_token.json` への原子的保存を実装済み
- Blogger: 画像アップロード API がないため、現在は Fedibird の画像 URL を HTML にホットリンク。恒久ホストへの移行が将来課題
- Phase 3: mixi2は専用Chromeからの実投稿まで完了。JotterのDOMと認証方式は一部調査済み。Instagram / mixi / Facebookは未着手。Xは規約上ブラウザ自動化しない
- 運用: Windows タスクスケジューラでの定期実行を確認済み。`--sync-only` で過去投稿をキューに積まず基準合わせできる
- ハードニング候補: Fedibird 取得のページング、HTTP タイムアウト、重複投稿抑止、排他制御、done/failed/state/media の清掃
