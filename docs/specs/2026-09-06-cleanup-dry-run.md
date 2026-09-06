# 清掃候補の読取り専用確認

- 日付: 2026-09-06
- 状態: dry-run・実清掃実装、自動テスト・実データdry-run確認完了（実データの削除は未実施）

## 方針

`bin/cleanup --dry-run` はファイルを削除せず、次の候補を分類・集計する。

- 指定日数以上経過した `done/*.json`
- 対応する `failed/*.json` がなく、指定日数以上経過した失敗スクリーンショット
- `queue/*.json` と `failed/*.json` のどちらからも参照されず、指定日数以上経過した
  `state/media/` の投稿別ディレクトリ
- ChromeのCache、Code Cache、GPU・Shader系キャッシュ、BrowserMetrics

既定は30日、各分類の一覧は10件まで。`--days N` と `--limit N` で変更できる。
Chromeキャッシュは生成時期にかかわらず再生成可能な容量として表示する。

## 保護対象

- `queue/` または `failed/` が参照する画像
- `failed/*.json`
- ChromeのCookie、Local Storage、IndexedDB、Service Worker、ログイン情報
- JotterのBrowser ID、DEN、暗号処理に関係する可能性があるIndexedDB

未処理ジョブJSONを一つでも解析できない場合、参照画像を確定できないためmedia候補を一切表示せず
警告する。安全側に倒し、不完全な情報から画像を削除可能とは判定しない。

## 初回確認

2026-09-06に30日基準で実データを確認し、古い完了ジョブ60件、未参照の古い画像36ディレクトリ、
再生成可能なChromeキャッシュ40ディレクトリを候補として抽出した。合計は136件、約1.47GB。
failed JSON 14件と参照中media 7ディレクトリは保護された。確認時点では削除を行っていない。

## 実清掃

dry-runで確認したのと同じ保持日数を `--apply --days N` に指定すると、古い完了ジョブ、孤立した
失敗スクリーンショット、未処理ジョブから参照されない古い画像を削除する。Chromeキャッシュは既定で
除外し、専用Chromeをすべて閉じたうえで `--include-browser-cache` を追加した場合だけ削除する。

削除処理はプロジェクト内の上記4分類に一致するパスだけを許可する。`failed/*.json`、参照中画像、
Cookie、Local Storage、IndexedDB、Service Worker、ログイン情報は対象外とする。途中で削除に
失敗した項目は表示して終了コード1を返す。初回の実データ清掃と保持期間の確定は、運用者が
直前のdry-run結果を再確認してから行う。
