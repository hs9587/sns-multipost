# Phase 3 ブラウザ投稿

- 日付: 2026-08-09
- 状態: 調査着手

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
- 添付はmultipleな `input[type="file"]`。JPEG / PNG / WebP / GIF / MP4 / QuickTime対応
- 通常ポストは約150文字枠。公開先は公開、プロフィールのみ、コミュニティから選ぶ

CLI実行用には `bin/browser_login mixi2` で専用Chromeを開き、ログイン状態を
Git管理外の `state/browser/mixi2` に保存する。次はこのプロファイルをFerrumから開き、
ログイン保持と投稿画面到達を確認する。

## 参照

- X Automation rules: https://help.x.com/en/rules-and-policies/x-automation
- mixi2 推奨環境: https://support.mixi.social/support/solutions/articles/154000228002
- mixi2 ポスト投稿: https://support.mixi.social/support/solutions/articles/154000228580
- mixi2 画像・動画投稿: https://support.mixi.social/support/solutions/articles/154000248606
- mixi PC日記投稿: https://mixi.jp/help.pl?item=1036&mode=item
