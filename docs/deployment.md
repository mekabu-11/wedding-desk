# Render + Supabase への公開

実際の操作を上から順に進めるチェックリストは [remote-deployment-runbook.md](remote-deployment-runbook.md) を参照する。このページは構成の判断と制約を説明する。

このアプリは、Render の Web Service と Supabase PostgreSQL を使い、スマホ・PCのブラウザから同じURLで利用できる。`render.yaml` を用意してあるため、Render では GitHub リポジトリを指定して Blueprint として作成する。

個人利用から無料提供へ移る段階別の判断は [docs/deployment-roadmap.md](deployment-roadmap.md) にまとめている。無料枠は個人試験用とし、一般公開ではバックアップと常時稼働を確保できる構成へ移行する。

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

初回ログイン後に結婚式を作成し、「結婚式の設定 → ふたりで共有」から2人目のログインを追加する。2人目用の秘密値をRender環境変数やGitへ追加する必要はない。

## 動作と制約

- Render Free は 15 分間アクセスがないと停止する。次のアクセス時は起動までおよそ1分かかる。
- Free では常駐ワーカーを作れないため、Solid Queue はWebプロセス内で処理する。画面を開いている間は、AI解析を含むバックグラウンド処理も動く。
- Supabase Free は利用がない期間に停止することがある。常用開始後は、必要に応じて有料プランへ変更する。
- 公開URLはRailsのログイン画面で保護されるが、共有端末ではログアウトする。

### 添付ストレージ

添付を本番で使う場合はSupabase StorageのS3互換エンドポイントを設定する。Active Storageの公開URLは利用者へ直接配らず、アプリの認証済み資料URLを経由する。

```dotenv
ACTIVE_STORAGE_SERVICE=supabase
SUPABASE_STORAGE_ENDPOINT=https://<project-ref>.storage.supabase.co/storage/v1/s3
SUPABASE_STORAGE_BUCKET=wedding-documents
SUPABASE_STORAGE_REGION=us-east-1
SUPABASE_STORAGE_ACCESS_KEY_ID=サーバー専用キー
SUPABASE_STORAGE_SECRET_ACCESS_KEY=サーバー専用シークレット
```

S3キーはブラウザやGitへ出さない。本番で上記の値が揃わない場合、Active Storageの本番サービス初期化または添付保存が安全に失敗する。ローカルDockerでは`storage_data` named volumeへ保存するため、通常の`docker compose down`では添付を残せる。添付ファイルは1個20MB、1資料10個、合計50MB、画像40MP、PDF20ページまでである。

xlsx初回移行は1ファイル25MB、最大2ファイル、展開後100MB、合計10,000行まで。XML解析はWebリクエスト内で行うため、公開環境ではリバースプロキシのアップロード上限とリクエストタイムアウトをこの値以上に設定し、大きな移行はメンテナンス時間帯に実施する。

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
