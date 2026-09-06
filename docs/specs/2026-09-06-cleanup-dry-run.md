# 清掃候補の読取り専用確認

- 日付: 2026-09-06
- 状態: dry-run実装・自動テスト・実データ確認完了

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

実削除と保持期間の確定は、dry-run結果を運用者が確認した後の別作業とする。
