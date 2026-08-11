# Blogger画像ストア実証と実装

## 結論

Bloggerの投稿編集画面をブラウザ自動操作すると、ローカル画像を
`blogger.googleusercontent.com` へアップロードできる。
Blogger API v3には画像アップロード口がないため、画像だけをブラウザで保存し、
取得した恒久URLを既存のAPI投稿へ渡す混合方式を採用した。

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

## 通常投稿への接続

- Blogger APIで非公開の一時下書きを作り、専用Chromeで画像を挿入する。
- `/s320/` の表示用URLを `/s0/` に変換し、公開画像として取得できることを確認する。
- URL取得後に一時下書きをBlogger APIで削除する。
- 画像SHA-256と元画像URLをキーに `state/blogger_image_store.json` へURLを保存する。
- プロセス中断に備えて一時下書きIDも同ファイルへ先に保存し、次回画像投稿時に削除する。
- ブラウザ操作失敗時は対応する `failed/*.png` を保存する。

## 通常投稿の実地確認

2026-08-11に `post --target blogger --from-fedibird-latest` で作ったジョブを
`run_queue` から実行し、次を確認した。

- Blogger公開記事へ画像付きで投稿できた。
- 記事の画像は `blogger.googleusercontent.com` の `/s0/` URLになった。
- 画像URLは認証なしでHTTP 200、`Content-Type: image/png` を返した。
- 作業用下書きは処理後に削除され、キャッシュへ画像URLが保存された。
- 最初のブラウザクリック失敗は画面保存から原因を特定し、再試行で正常終了した。

自動テストと実際のBlogger画像付き投稿による最終確認は完了している。
