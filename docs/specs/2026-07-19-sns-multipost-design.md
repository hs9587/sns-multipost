# sns-multipost 設計ドキュメント

- 日付: 2026-07-19
- 状態: ユーザー承認済み設計（brainstorming 完了）
- リポジトリ: GitHub `hs9587/sns-multipost`（パブリック・新規作成）

## 1. 目的と背景

きっかけ投稿（Fedibird @hs9587）を検出し、同一内容を複数 SNS へ自動投稿する。
動機は MT変換機の開発データ作成 —「いろんな SNS に投稿している状態」を作る。

旧 `hs9587/SNS_multi_post`（Ruby+Selenium+Edge、cookie 移植方式、現在は動かない）の**後継**として全面的に作り直す。旧リポジトリはアーカイブ扱いで残す。新 README の冒頭に「旧 SNS_multi_post の後継として作り直したもの」である旨と旧リポジトリへのリンクを置く。

## 2. 決定事項サマリ

| 項目 | 決定 |
|------|------|
| 実装言語 | 全 Ruby（ブラウザ部は playwright-ruby-client） |
| 実行形態 | 非常駐。ファイルキュー、タスクスケジューラ駆動 |
| 投稿先 | X / Instagram(→Facebook・Threads 連携シェア) / mixi旧 / mixi2 / Bluesky / Blogger / Tumblr / Jotter.me |
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
    queue.rb              ジョブの生成・遷移（queue/ → done/ | failed/）
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
| API組 | Bluesky / Tumblr / Blogger / Fedibird | 各 REST API（HTTP+JSON、gem は最小限） |
| API組(条件付) | X | API v2 free tier。枠・規約で詰まったらブラウザ組へ降格 |
| ブラウザ組 | Instagram / mixi旧 / mixi2 / Jotter.me | playwright-ruby-client。`state/profiles/` にログイン済みプロファイル永続化 |

- Instagram はハブ: アカウント連携設定で Facebook・Threads へ同時シェア（本ツールは Instagram にだけ投稿する）
- ブラウザ組は失敗時にスクリーンショットを failed/ のジョブ横に保存（Claude 修理の一次資料）
- Jotter.me は **v1 テキスト投稿のみ**。画像投稿にはブラウザごとに DEN の用意が必要（DEN の残高は振替機能で用意する）で、これは次ステップとしてスコープ外

### 要調査（実装フェーズ最初に小さく検証）

1. mixi2 の Web からの投稿可否
2. Jotter.me の投稿フォーム構造
3. Instagram の自動化検知の程度
4. X API free tier の投稿枠が月間投稿数に足りるか

## 8. タイトル辞書

タイトル欄のある SNS（Blogger 必須・mixi日記 必須・Tumblr 任意）向けに、`title_rules.yml` を上から順に評価:

1. **おはよう**: 本文に「おはよう」→ タイトル「おはよう」
2. **コーヒー**: コーヒー語彙（コーヒー、珈琲、ホット、アイス、アメリカン、ブレンド、ブリュー、モカ、キリマンジャロ、マンデリン等の産地・銘柄）、または非コーヒー飲料語（ティー、紅茶、ジュース等）が無く飲み物文脈（行きつけ店名リスト等）がある場合コーヒー扱い。タイトルは アイス系語彙→「アイス」、産地・銘柄→その名、他→「ホット」
3. **食べ物リスト**: パン、ブレッド、スパゲティ、そば、ごはん、おにぎり等 → 最初にマッチした語
4. **フォールバック**: 本文冒頭12字＋「…」

辞書は「ドライラン＋指摘」で育てる: `bin/dryrun_titles` が Fedibird 公開 API で過去投稿200〜500件を取得し「投稿→タイトル」一覧表を出力。違和感のある行の指摘を受けて Claude が辞書に規則を追加する。X の過去分はアーカイブ zip の取り込み口を将来追加可能。

## 9. エラー処理・修理運用

- 失敗ジョブは `failed/` に残る（本文・タイトル・画像パス・エラーメッセージ・スクショ付き）
- `bin/retry failed/xxx.json` で単体再実行
- 「mixi が壊れた」→ failed のジョブ＋スクショを Claude に見せ、`lib/poster/mixi.rb` を修理 → retry で確認
- 1ジョブ1SNS なので、1サービスの故障が他SNSのジョブを巻き添えにしない

## 10. テスト

- 単体テスト: タイトル辞書（最重要・回帰しやすい）、ジョブ生成・キュー遷移
- 各ポスターに `dry_run` モード（投稿直前まで進めて止まる）。ブラウザ組はログイン〜投稿画面到達の smoke test
- 本物投稿の確認は各SNS 1回ずつ手動キック

## 11. 秘匿情報の扱い

- `config.yml`（APIキー・トークン・アカウント名・Jotter セーブポイント等）と `state/`（cookie・ブラウザプロファイル）は `.gitignore`
- `config.sample.yml` を雛形としてコミット。SETUP.md に「何をどこから取得してどの欄に書くか」を記載
- **秘匿値はリポジトリ外**: config.sample.yml を雛形に、利用者本人が config.yml に直接記入する（アカウント名・ユーザーID程度は設計上必要になれば共有可）
- **別マシンへの移行**: APIキー類は本人管理の経路（USB・パスワードマネージャ等、Git 経由にしない）で持ち込み移行先の config.yml に記入。ブラウザログイン状態は**移植せず移行先で別採取**（初回手動ログイン）。機体ごとに独立させ、cookie 移植はしない

## 12. 移設・運用

- 開発: 在宅機 `sns-multipost`。本番: 稼働中の Windows 機（Claude Code 導入済み）
- 移設手順（SETUP.md に記載): git clone → `bundle install` → playwright ブラウザ install → config.yml 記入 → ブラウザ組4サービスへ初回手動ログイン → schtasks でスケジューラ登録（bin/watch 5分おき、bin/run_queue その直後）

## 13. スコープ外（次ステップ候補）

- Jotter.me の画像投稿（DEN の用意が必要。DEN 残高は振替機能で用意）
- 出先対応のトリガ差し替え（Fedibird 監視の常駐化等）
- タイトル判定の LLM ハイブリッド（c案）
- note への投稿（対象外と決定済み）
