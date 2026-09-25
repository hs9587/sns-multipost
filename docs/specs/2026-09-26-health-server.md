# 読み取り専用状態確認サーバー

## 目的

PCの蓋を閉じた運用中に、家庭内LANまたは既存VPN上の別端末から、PCとsns-multipost定期タスクの
稼働状態を確認する。投稿や復旧操作を遠隔実行する管理画面にはしない。

## 構成

- RubyのWEBrickを使用する
- 投稿タスク `sns-multipost` とは別の長時間プロセスとする
- 常時起動用Windowsタスク名は `sns-multipost-health`
- 管理コマンドは `bin/health`、サーバー本体は `bin/health_server`
- 稼働状態はGit管理外の `state/health_server.json` に保存する
- ログはGit管理外の `logs/health.log` と `logs/health-launch.log` に保存する

## 待受先

- `home` / `lan`: 既定ゲートウェイを持つ物理LANを選び、プライベートネットワークだけ許可する
- `nebula`: 名前にNebulaを含む既存アダプターを選ぶ
- IPv4: このPCへ実際に割り当て済みのアドレスだけ許可する
- 候補がない、複数ある、未割当、`0.0.0.0` の場合は安全側で起動を拒否する

IPやNebula固有設定を `config.yml` に追加しない。`nebula` 指定は起動のたびにアダプターを探索し、
IP直指定でWindowsタスクへ登録した場合だけ、その非秘密IPがタスクの起動引数に残る。

## HTTP

- `GET /`: 人向けHTML
- `GET /health.json`: 同じ内容のJSON
- `HEAD`: 許可
- それ以外のメソッドは405
- それ以外のパスは404
- `Cache-Control: no-store` 等の安全用ヘッダーを付ける

表示対象はサーバー時刻・起動情報、投稿タスク状態、定期実行ラッパーの直近結果と最後の異常、
done最新、done最新と同時刻以降に残るfailedの件数とジョブ名に限定する。

## 公開しないもの

- `config.yml` と認証情報
- Cookie、トークン、ブラウザプロファイル
- 投稿本文と画像
- 任意ファイル
- Nebulaの証明書、秘密鍵、CA、lighthouse設定
- 投稿、retry、タスク切替、ファイル削除などの更新操作

## ネットワーク境界

ファイアウォールを自動変更しない。インターネットへ直接公開せず、家庭内LANまたは既存VPNの
範囲だけで使用する。Nebulaは任意の対応例であり、必須依存ではない。他のVPNでも、このPCへ
割り当て済みのIPを直接指定できる。
