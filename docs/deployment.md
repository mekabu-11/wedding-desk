# Render + Supabase への公開

このアプリは、Render の Web Service と Supabase PostgreSQL を使い、スマホ・PCのブラウザから同じURLで利用できる。`render.yaml` を用意してあるため、Render では GitHub リポジトリを指定して Blueprint として作成する。

## 公開手順

1. Supabase で新規プロジェクトを作成する。リージョンは利用者に近い Tokyo を選ぶ。
2. Supabase の **Connect** から **Session pooler** の接続文字列を取得する。`sslmode=require` を含む URI を使う。Render からの接続には Direct connection や Transaction pooler ではなく Session pooler を使う。
3. Render の Dashboard で **New > Blueprint** を選び、この GitHub リポジトリを接続する。検出された `render.yaml` をそのまま使う。
4. Render が入力を求める次の値を設定する。値はGitに保存しない。

   | 変数 | 設定する値 |
   | --- | --- |
   | `DATABASE_URL` | 手順2のSupabase Session pooler接続URI |
   | `APP_EMAIL` | このアプリにログインするメールアドレス |
   | `APP_PASSWORD` | 12文字以上の新しいログインパスワード |

   `SECRET_KEY_BASE` と `AR_ENCRYPTION_*` は Render が初回作成時に自動生成する。生成後は変更・削除しない。変更すると既存の暗号化済み本文を読めなくなる。

5. Deploy を実行する。起動時にDBマイグレーションと初期ユーザー作成を行う。デプロイ完了後、Render が表示する `https://...onrender.com` を開き、手順4のメールアドレスとパスワードでログインする。
6. Render の設定で自動デプロイを有効にしておく。`main` への push が次回以降の更新になる。

## 動作と制約

- Render Free は 15 分間アクセスがないと停止する。次のアクセス時は起動までおよそ1分かかる。
- Free では常駐ワーカーを作れないため、Solid Queue はWebプロセス内で処理する。画面を開いている間は、AI解析を含むバックグラウンド処理も動く。
- Supabase Free は利用がない期間に停止することがある。常用開始後は、必要に応じて有料プランへ変更する。
- 公開URLはRailsのログイン画面で保護されるが、共有端末ではログアウトする。

## バックアップ

Supabase Free には自動バックアップがない。公開後は少なくとも月1回、Supabaseの Database Backups か `pg_dump` でバックアップを取得し、アプリの暗号化キーとは別に安全に保管する。暗号化キーを失うと、バックアップがあっても暗号化済みの本文は復元できない。

## ローカル Docker 開発

`bin/setup` のみで構築する。ホストに Ruby・PostgreSQL を入れない。

```sh
docker compose logs --tail=50 web worker
docker compose run --rm -e RAILS_ENV=test web bin/rails db:prepare
docker compose run --rm -e RAILS_ENV=test web bin/rails test
```

Compose名は `wedding-desk-github`。`.env` はGitおよびDocker build contextから除外する。`docker compose down -v` はローカルDB volumeも削除するため、通常の停止には使わない。

## Dockerホストへ直接配置する場合

`compose.production.yaml` はRenderを使わず、独自のDockerホストに置く場合の構成である。TLSを終端するリバースプロキシを用意し、`APP_HOST`、本番用の秘密値、PostgreSQLの `DATABASE_URL` を設定する。
