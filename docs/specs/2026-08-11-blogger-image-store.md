# Blogger画像ストア実証

## 結論

Bloggerの投稿編集画面をブラウザ自動操作すると、ローカル画像を
`blogger.googleusercontent.com` へアップロードできる。
Blogger API v3には画像アップロード口がないため、画像だけをブラウザで保存し、
取得した恒久URLを既存のAPI投稿へ渡す混合方式が実装候補になる。

## 2026-08-11の実地確認

- 専用ChromeプロファイルでBloggerへログインした。
- 無題の下書きを作り、「画像を挿入」→「パソコンからアップロード」を自動操作した。
- `docs.google.com` の画像追加フレーム内にある `input[type=file]` へPNGを渡した。
- Chromeを閉じて下書きを開き直しても画像が表示された。
- 本文編集フレームから `https://blogger.googleusercontent.com/img/.../s320/01.png` を取得した。
- サイズ指定を `/s0/` に変更したURLへ認証なしでHEADリクエストし、
  HTTP 200、`Content-Type: image/png` を確認した。
- 記事は公開していない。

実証中に同じ画像を2回アップロードしたため、Blogger側では別々のURLが発行された。
実証用の無題下書きは自動削除せず、投稿一覧から手動で削除する。

## 再現方法

```powershell
ruby bin/browser_login blogger
ruby spike/blogger_image_upload.rb PATH_TO_IMAGE
```

実証スクリプトは記事を公開しない。画像入りの無題下書きを残すので、確認後に手動で削除する。

## 本実装へ進む際の課題

- 画像アップロードと既存Blogger API投稿を一つの処理として扱う。
- `/s320/` の表示用URLから `/s0/` の元サイズURLを作り、取得可能性を検証してから使う。
- 途中失敗時に作られた無題下書きと、アップロード済み画像の扱いを決める。
- UI変更、Google画像追加フレームの遅延、Chromeプロファイルロックへ備える。
- 同じ画像の再試行で別URLが増えるため、ジョブ単位でアップロード済みURLを保存して再利用する。

