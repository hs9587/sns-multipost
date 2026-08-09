# Phase 3 ブラウザ投稿

- 日付: 2026-08-09
- 状態: mixi2ポスター実装・smoke・実投稿確認完了

## 方針

ブラウザ投稿は、公式APIが使えない投稿先に限って採用する。サービスごとに
利用条件、ログイン維持、投稿画面のDOM、画像上限、投稿完了判定を先に確認し、
失敗時はジョブと同じ識別子でスクリーンショットを保存できる構成にする。

## 暫定優先順

1. mixi2: 公式にChrome対応のブラウザ版と、テキスト・画像最大4件の投稿を提供。
   最初の画面調査対象とする
2. mixi: PCブラウザから日記投稿が可能。タイトル導出をそのまま活用できる
3. Jotter.me: Ferrumスパイクで投稿フォームまで確認済みだが、セーブポイント処理後の
   安定したログイン完了判定とコンポーザーへの自動遷移が未解決
4. Instagram: 対象アカウントで公式投稿APIが使えるならAPIを優先し、ブラウザ方式は
   その結果を見て判断する
5. Facebook個人プロフィール: 公式投稿APIの対象外。ブラウザ方式の利用条件と安定性を
   確認してから着手する

Xは公式Automation rulesがWebサイトのスクリプト操作を禁止しているため、
ブラウザ自動投稿の対象外とする。APIクレジットを購入しない間は、本文をクリップボードへ
用意して公式Webを開き、利用者が投稿する手動引き渡し方式を候補とする。

## mixi2 最初の確認

ログインはMIXI IDのメールアドレス、メールで届く認証コード、利用ID選択の3段階。
メールアドレスや認証コード自体は設定・文書・ログへ保存しない。

ログイン後のホームと投稿フォームを、外部投稿せずに確認した結果:

- ホーム右上はアクセシブル名 `ポスト` のbutton
- 投稿画面はアクセシブル名 `新規ポスト作成` のdialog
- 本文欄は `.tiptap.ProseMirror[contenteditable="true"]`
- 送信は `button[type="submit"][aria-label="送信"]`。本文が空ならdisabled
- 添付は `input[type="file"]`。JPEG / PNG / WebP / GIF / MP4 / QuickTime対応。
  実行環境によりmultiple属性が無いため、最大4枚を1枚ずつ追加する
- 通常ポストは約150文字枠。公開先は公開、プロフィールのみ、コミュニティから選ぶ

CLI実行用には `bin/browser_login mixi2` で専用Chromeを開き、ログイン状態を
Git管理外の `state/browser/mixi2` に保存する。次はこのプロファイルをFerrumから開き、
ログイン保持と投稿画面到達を確認する。Ferrumは既定でincognitoコンテキストを作るため、
永続プロファイル利用時は `incognito: false` を必ず指定する。またFerrum 0.17.2は
トップレベルの `user_data_dir:` を認識しないため、`browser_options` の
`user-data-dir` でChrome起動引数を上書きする。

`bin/mixi2_smoke` により、専用プロファイルのログイン保持、ホーム到達、投稿画面の
本文欄・送信ボタン・メディア入力を確認し、投稿せず閉じるところまで成功した。
`Poster::Mixi2` は本文を150 graphemeへ収め、画像を先頭4枚に制限してFerrumへ渡す。
`bin/post` が作成したmixi2ジョブを `bin/run_queue` で処理し、投稿URLが返ることと、
別ブラウザから公開投稿を閲覧できることを確認済み。実際の投稿URLやログイン情報は
文書・Gitへ保存しない。

Fedibird監視からの初回画像付き投稿では本文だけが公開された。ジョブには画像パスがあり、
ローカル画像も存在したため、原因はファイル選択後0.5秒で送信していたアップロード待ち不足と
判断。画像ごとにFerrumの通信が添付前の水準へ戻るまで最大30秒待ち、さらにUI反映を待って
から送信するよう修正した。残作業は画像付き再確認と失敗時スクリーンショットの保存。

## 参照

- X Automation rules: https://help.x.com/en/rules-and-policies/x-automation
- mixi2 推奨環境: https://support.mixi.social/support/solutions/articles/154000228002
- mixi2 ポスト投稿: https://support.mixi.social/support/solutions/articles/154000228580
- mixi2 画像・動画投稿: https://support.mixi.social/support/solutions/articles/154000248606
- mixi PC日記投稿: https://mixi.jp/help.pl?item=1036&mode=item
