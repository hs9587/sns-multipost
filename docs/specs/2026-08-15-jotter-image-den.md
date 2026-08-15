# Jotter画像投稿とDEN運用

- 日付: 2026-08-15
- 状態: 専用Browser ID、DEN振替・検証、先頭画像1枚の公開投稿を実地確認済み

## 方針

Jotterの画像投稿にはDENが必要で、利用可能DENが不足している状態では投稿しない。
複数画像は1枚ごとにDEN状態が変わり、途中失敗しやすいため、sns-multipostではmixiと同様に
先頭画像1枚だけを使う。投稿フォームが示す実費を読み取り、固定額だけを根拠に送信しない。

DENとBrowser IDの生値はログ、文書、Git管理ファイルへ保存しない。専用ChromeのBrowser IDは
SHA-256の短いfingerprintだけを `state/jotter_wallet.json` に保存する。このファイル、Chrome
プロファイル、失敗スクリーンショットはいずれもGit管理外とする。

## 実地確認

- 専用Chromeを再起動してもBrowser IDのfingerprintは一致した
- 画像1枚を選ぶと、確認環境では `Total Cost: 90 DEN` と表示された
- 100 DENの振替は、利用可能0・未検証100として反映された
- 未検証を押すと検証が段階的に進み、約1分後に利用可能100・未検証0になった
- 利用可能DENは時間経過後や画像投稿後に未検証へ戻る場合がある
- 画像1枚の公開投稿と、新しい公開投稿URLの取得に成功した
- 画像投稿後の10 DENへ5,555 DENを3回振り替え、利用可能16,675 DENとして計算どおり反映された

実費は場所や通信状態により90 DENより高く表示される場合があるため、実装は投稿フォームの表示を
優先する。公開投稿URL、Browser ID、口座IDは記録しない。

## コマンド

読み取りだけで専用Browser IDとDENを確認する。

    ruby bin/jotter_wallet_smoke

専用Chromeのウォレットを開いたまま保持し、別ブラウザから手動振替する。反映後にEnterを押す。
このコマンド自体は送金、振替、検証要求を行わない。

    ruby bin/jotter_wallet_hold

未検証DENへ検証要求し、指定額が利用可能になるまで待つ。送金、振替、投稿は行わない。

    ruby bin/jotter_wallet_verify
    ruby bin/jotter_wallet_verify --required 900

画像選択、プレビュー、必要DENだけを確認し、投稿もDEN支払いもしない。

    ruby bin/jotter_media_smoke photo.jpg

公開画像投稿は通常のキュー経路を使う。

    ruby bin/post --target jotter --image photo.jpg "本文"
    ruby bin/run_queue

## 自動投稿時の処理

1. 専用Chromeでウォレットを読み、保存済みBrowser IDが画面に出ていればfingerprintを照合する
2. Browser IDが一時的に非表示なら、実地確認済みの専用Chromeプロファイルを継続使用する
3. 利用可能DENが90未満でも、未検証分を含めて足りる場合は検証要求し、利用可能になるまで待つ
4. 投稿フォームで先頭画像1枚を選び、画面に表示された実費を読む
5. 実費分の利用可能DENがなければ送信せず、ジョブを `failed/` に残す
6. 投稿後に新しい公開URLを確認できた場合だけ成功とする

振替は自動化しない。残高不足時は `jotter_wallet_hold` で専用ウォレットを開き、利用者が別ブラウザ
からまとめて振り替える。利用可能DENが再び未検証になった場合は、次の画像投稿時または
`jotter_wallet_verify` の明示実行時に再検証する。
