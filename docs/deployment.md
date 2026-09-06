# Dockerによる配置と運用

## 開発

`bin/setup` のみで構築する。ホストにRuby・PostgreSQLを入れない。

- web：Rails/Puma、ホストの127.0.0.1:3210に限定
- worker：Solid Queue（独立プロセス）
- db：PostgreSQL 17、named volume、ホスト公開なし

Compose名は `wedding-desk-github`。他アプリのコンテナ・DB・ネットワークを操作しない。

暗号化鍵、SECRET_KEY_BASE、DBパスワードを `.env` に保存する。`.env` はGitおよびDocker build contextから除外する。Composeの展開済み設定には秘密値が含まれるため、その出力を公開しない。

```sh
docker compose logs --tail=50 web worker
docker compose run --rm -e RAILS_ENV=test web bin/rails db:prepare
docker compose run --rm -e RAILS_ENV=test web bin/rails test
```

ソースは開発時だけbind mountする。Gemを変更した場合はイメージを再ビルドする。ワーカーはコード変更後に `docker compose restart worker`。

## 本番向け構成案（未デプロイ）

常駐Web・常駐ワーカー・PostgreSQLが動くDockerホストを使う。Vercelへの配置はこの構成の対象外。

`compose.production.yaml` は開発用bind mountを外し、production環境と別DBを指定する。Composeの `!reset` が使えるバージョンが必要。今回の検証環境はCompose v2.40.3。

1. 本番ホストにDockerを用意する。
2. `.env` を安全に配置し、ランダムな秘密値を設定する。開発と異なる値を使用し、DBパスワードにはURLへそのまま入れられる英数字・hexを使う。
3. `APP_HOST` を使用するドメインにする。AIキー・モデルを設定する。
4. TLSを終端するリバースプロキシを構成し、Webへ転送する。ホスト名検証・HTTPS強制・Secure Cookieを維持する。
5. 次を実行する。

```sh
docker compose -f compose.yaml -f compose.production.yaml build
docker compose -f compose.yaml -f compose.production.yaml up -d db
docker compose -f compose.yaml -f compose.production.yaml run --rm web bin/rails db:prepare app:bootstrap
docker compose -f compose.yaml -f compose.production.yaml up -d web worker
```

productionでは平文HTTPアクセスをHTTPSへリダイレクトする。TLSプロキシなしで公開しない。既存の開発環境と同一ホストで併用する場合は `-p` でCompose名を分け、APP_PORTと秘密値も分離する。

## 秘密値・バックアップ

- `.env` の暗号化鍵を失うと本文を復元できない。DBのバックアップとは別に安全に保管する。
- アプリDBとキューDBのバックアップ、定期的な復元検証を行う。
- 本番利用開始前にバックアップの暗号化、保持期間、削除期限を確定する。
- `docker compose down -v` はDB volumeも削除するので、通常の停止には使わない。
- この段階では外部ユーザー向け招待・パスワード再発行・管理画面を提供していない。

本番のTLS、バックアップ復元、実APIのデータ保持設定は今回のローカル検証には含めない。
