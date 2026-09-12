# リモート公開手順書（GitHub → Render＋Supabase）

この手順は、現在のRailsアプリをGitHubへpushし、Render FreeのWeb ServiceとSupabase FreeのPostgreSQL・Storageで個人用の遠隔環境を作るためのものです。Render Freeは停止・一時ディスク・無バックアップの制約があるため、無料一般公開ではなく個人試験に使います。

このリポジトリの現在の公開対象は、`codex/wedding-management-v1` のコミット `c2a1705` です。公開作業は「GitHubへpush → Supabaseを用意 → Render Blueprintを作成 → `/up` とログインを確認」の順に進めます。Renderへ直接pushするのではなく、GitHub上のブランチをRenderがビルドします。

## 0. 公開前の前提

- プロジェクトは /Users/zunya/Documents/GitHub/wedding-desk にある。
- 現在のブランチは codex/wedding-management-v1。
- 作業ツリーが空で、bin/verify が成功したリビジョンだけをpushする。
- .env、DBパスワード、Rails暗号化キー、Supabaseの秘密鍵はGitHubへpushしない。
- 既存の本番データがある場合は、先にDB・添付ファイル・暗号化キーをバックアップする。キーを失った状態でDBだけ復元しても暗号化済み本文は読めない。

### 作業前チェック

- GitHubのリポジトリが非公開で、push先が自分の管理するリポジトリであることを確認する。
- Supabaseのプロジェクトを本番用に新規作成し、DBパスワードとStorageの秘密値をパスワード管理ツールへ保存する。
- Render、Supabase、GitHubへログインできることを確認する。パスワードや接続URIをIssue・チャット・スクリーンショットへ貼らない。
- 初回は架空データで動作確認し、実データを移す場合は先にローカルのDB・添付・暗号化キーを別媒体へバックアップする。

## 1. ローカルで公開リビジョンを確認する

```sh
cd /Users/zunya/Documents/GitHub/wedding-desk
git status --short
git branch --show-current
git rev-parse --short HEAD
bin/verify
```

git status --short に意図しない変更がなく、bin/verify が成功してからpushする。今回の確認結果は次のとおり。

```
122 runs / 985 assertions / 0 failures / 0 errors / 0 skips
```

`git status --short` が空で、ブランチが `codex/wedding-management-v1`、コミットが `c2a1705` であることを確認する。テスト結果が異なる場合は、先に失敗原因を解消する。

## 2. GitHubへpushする

まだGitHubリポジトリがなければ、先に非公開リポジトリを作成する。現在のリモートは `https://github.com/mekabu-11/wedding-desk.git` である。別のリポジトリへ公開する場合は、先に `git remote set-url origin ...` で宛先を変更する。

```sh
cd /Users/zunya/Documents/GitHub/wedding-desk
git remote -v
git remote add origin git@github.com:<GitHubユーザー名>/wedding-desk.git
git push -u origin codex/wedding-management-v1
```

すでにoriginがある場合はgit remote addを繰り返さず、URLを確認してpushする。

```sh
git remote get-url origin
git push origin codex/wedding-management-v1
```

個人用の初回公開では、このブランチをRenderから直接指定してよい。運用を固定する場合は、GitHubでPull Requestを作成してmainへマージし、Renderはmainを自動デプロイ対象にする。

push後にGitHubの **Commits** で `c2a1705` が表示されることを確認する。Renderの設定前に、GitHub上のファイル一覧で `render.yaml`、`Dockerfile`、`bin/render-start`、`db/migrate/20260912000003_add_unique_cash_gift_fallback_conditions.rb` が存在することを確認する。

## 3. Supabaseプロジェクトを作る

1. Supabaseで新しいプロジェクトを作成する。リージョンは利用場所に近いものを選ぶ。
2. Connectから、Renderから到達できる Session pooler のPostgreSQL接続URIを取得する。
3. URIにsslmode=requireが含まれていることを確認する。接続URIはパスワードを含むため、ブラウザ履歴・GitHub Issue・チャットへ貼らない。
4. Storageを使う場合は、非公開バケット（例：wedding-documents）を作成する。
5. StorageのS3互換接続情報から、サーバー専用のAccess KeyとSecretを取得する。Anon keyやService Role keyをブラウザへ渡さない。

SupabaseのDBパスワードとStorageのS3キーは別々に保管する。Renderの環境変数へ入力する値は、前後の空白や引用符を含めない。接続URIにパスワードの記号が含まれる場合は、Supabaseが表示したURIをそのまま使い、手で組み立て直さない。

### Supabaseで控える値

| 値 | 使い道 |
| --- | --- |
| Session poolerの接続URI | RenderのDATABASE_URL |
| Storage S3 endpoint | SUPABASE_STORAGE_ENDPOINT |
| バケット名 | SUPABASE_STORAGE_BUCKET |
| S3 region | SUPABASE_STORAGE_REGION。通常はus-east-1 |
| S3 access key | SUPABASE_STORAGE_ACCESS_KEY_ID |
| S3 secret | SUPABASE_STORAGE_SECRET_ACCESS_KEY |

### Supabase接続の確認

Renderへ設定するのは、Supabaseの **Connect → Session pooler** に表示される接続URIである。Direct connectionやTransaction poolerへ置き換えない。URIのホスト、ポート、データベース名、ユーザー名、`sslmode=require` を確認し、ローカルの `.env` やGitへ保存しない。

Storageをまだ使わない場合でも、DB接続だけで初回Deployはできる。ただし本番の `ACTIVE_STORAGE_SERVICE` は既定で `supabase` なので、画像・PDFを登録する前にStorage変数をすべて設定する。

## 4. RenderでBlueprintを作る

1. Render Dashboardで New → Blueprint を選ぶ。
2. GitHubリポジトリを接続し、wedding-deskを選ぶ。
3. 個人用試験ならブランチにcodex/wedding-management-v1を指定する。mainへマージして運用する場合はmainを指定する。
4. リポジトリのrender.yamlを読み込ませる。
5. Renderが入力を求める秘密値を設定する。

Blueprint作成時は、既存のWeb Serviceを誤って選ばず、新しいWeb Serviceとして作成する。サービス名は `render.yaml` の `wedding-desk-private-mekabu-11` を基準にし、公開URLを一般公開する前にアクセス範囲とデータ削除手順を決める。

### Renderで設定する環境変数

render.yamlで自動設定される値は再入力しない。generateValue: trueの4つのキーはRenderが生成した値をそのまま使い、後から変更・削除しない。

| 変数 | 値 |
| --- | --- |
| DATABASE_URL | SupabaseのSession pooler接続URI |
| APP_EMAIL | 初期ログインに使うメールアドレス |
| APP_PASSWORD | 12文字以上の初期パスワード |
| SECRET_KEY_BASE | Renderの自動生成値 |
| AR_ENCRYPTION_PRIMARY_KEY | Renderの自動生成値 |
| AR_ENCRYPTION_DETERMINISTIC_KEY | Renderの自動生成値 |
| AR_ENCRYPTION_KEY_DERIVATION_SALT | Renderの自動生成値 |
| ACTIVE_STORAGE_SERVICE | 添付を使う場合はsupabase |
| SUPABASE_STORAGE_ENDPOINT | Supabase StorageのS3 endpoint |
| SUPABASE_STORAGE_BUCKET | 作成した非公開バケット名 |
| SUPABASE_STORAGE_REGION | S3 region。通常はus-east-1 |
| SUPABASE_STORAGE_ACCESS_KEY_ID | サーバー専用S3 access key |
| SUPABASE_STORAGE_SECRET_ACCESS_KEY | サーバー専用S3 secret |
| APP_HOST | 任意。カスタムドメインを使う場合だけそのホスト名 |
| OPENAI_API_KEY | AI整理を有効にするときだけ設定。GitHubへ保存しない |
| LLM_MODEL | `OPENAI_API_KEY`と組み合わせる利用可能なモデルID |

Storage変数は、添付を使わない初回でも後から追加できる。ただし本番で画像・PDFを保存する前には必ず設定する。

`render.yaml` にない `ACTIVE_STORAGE_SERVICE`、`SUPABASE_STORAGE_*`、`OPENAI_API_KEY`、`LLM_MODEL`、`APP_HOST` はRender Dashboardの **Environment** から手動追加する。`APP_HOST` を空欄にすると `RENDER_EXTERNAL_HOSTNAME` が使われるため、Render標準URLだけなら省略できる。既存の暗号化キーを使う環境では、キーをGenerateし直さず同じ値を設定する。

RAILS_ENV=production、SOLID_QUEUE_IN_PUMA=true、RAILS_MAX_THREADS=3、WEB_CONCURRENCY=1はrender.yamlに含まれている。FreeプランではSolid Queueを別Workerにせず、Webプロセス内で動かす個人試験構成にしている。

## 5. 初回Deployと起動確認

RenderのDeployを実行する。Dockerfileのビルド中にproduction用assetsを生成し、起動コマンド `bin/render-start` で次の順に実行される。

1. bin/rails db:prepare
2. bin/rails app:bootstrap
3. Rails Web Server起動

Deployログで、migrationが完了してから `Owner account created` または `Owner account already exists` が出ることを確認する。`APP_EMAIL` または `APP_PASSWORD` が空、パスワードが12文字未満、暗号化キーが不足している場合は起動を止める。

Renderのログでmigrationと起動を確認し、次のURLを開く。

```
https://<Renderサービス名>.onrender.com/up
```

200が返ったら、同じドメインのログイン画面でAPP_EMAILとAPP_PASSWORDを使ってログインする。初期アカウントが既に存在する場合、app:bootstrapでパスワードは上書きされない。

### 初回のスモークテスト

1. `https://<Renderサービス名>.onrender.com/up` がHTTP 200になることを確認する。
2. ログインして結婚式を1件作成する。
3. ゲスト、世帯、卓、ご祝儀区分、食事セットを1件ずつ登録する。
4. 卓の位置を移動して保存し、再表示後も位置が残ることを確認する。
5. 概算の費用を1件作成し、入出金履歴を追加して支払状況が変わることを確認する。
6. 設定画面から2人目を追加し、別ブラウザまたはプライベートウィンドウで同じWeddingを見られることを確認する。
7. Storageを設定した場合は、画像またはPDFの登録・表示・ログアウト後のアクセス拒否を確認する。
8. CSVエクスポートを実行し、関連ID・食事セット・卓位置が含まれることを確認する。

## 6. 初回ログイン後の確認順

個人用の架空データまたは少量の実データを使い、次の順で確認する。初回は削除可能な架空データだけで実施する。

1. 結婚式を作成する。
2. 「結婚式の設定 → ふたりで共有」から2人目のアカウントを追加する。
3. ゲスト、世帯、卓を1件ずつ登録する。
4. ご祝儀区分、食事セット、引き出物セットを登録する。
5. お金を1件登録し、入出金履歴を1件追加する。
6. 卓の一覧から「卓の位置を編集」を開き、配置を保存する。
7. 添付を使う場合、画像またはPDFを登録して認証済みURLから開く。
8. CSVエクスポートを実行し、meal_sets.csv、ゲストのmeal_set_id、卓のposition_x/position_yが含まれることを確認する。
9. 2人目のアカウントで同じデータを見られることを確認する。

Freeプランでは初回アクセスに起動待ちがある。ログイン画面がすぐ表示されなくても、RenderのDeployログと/upを確認してから再読み込みする。

## 7. 以後の更新

ローカルで変更を確認してから、使っているブランチへpushする。

```sh
cd /Users/zunya/Documents/GitHub/wedding-desk
bin/verify
git status --short
git add <変更したファイル>
git commit -m "変更内容"
git push origin codex/wedding-management-v1
```

Renderの自動Deployが有効ならpushを検知して再ビルドする。production起動時にdb:prepareが実行されるため、新しいmigrationも起動時に適用される。Deploy中に暗号化キーを変更しない。

### 更新前後の確認

1. ローカルで `bin/verify` を実行し、作業ツリーと対象コミットを確認する。
2. migrationを含む変更では、先にバックアップを取得する。
3. 対象ブランチへpushし、GitHub Actionsやコミット画面で対象コミットを確認する。
4. RenderのDeployログでDocker build、migration、bootstrap、Web起動の順を確認する。
5. `/up`、ログイン、変更した導線をスモークテストする。
6. 問題がなければDeployの完了時刻とコミットを運用メモへ残す。

DB migrationは後方互換性を保つ。アプリが新しいカラムを使う前にカラムを追加し、不要なカラム削除や厳しい制約追加は別Deployに分ける。migration失敗時はアプリを再起動し続けず、RenderログとSupabaseのmigration状態を確認する。

main運用へ切り替えた後は、Pull Requestをマージして次で更新する。

```sh
git push origin main
```

### 直前のバージョンへ戻す場合

RenderのDeploy一覧から、直前に正常だったコミットのDeployを選んで再Deployする。DB migrationを含むリリースは、アプリだけを戻すと新旧コードの不整合が起きるため、先にmigrationの後方互換性とバックアップを確認する。破壊的なmigrationを戻す場合は、DBの復元を含む復旧手順として扱う。

## 8. 障害時の確認

### ログインできない

- Renderの環境変数でAPP_EMAILとAPP_PASSWORDを確認する。
- 既存ユーザーのパスワードはapp:bootstrapでは変更されない。初期パスワードを変数に入れ直しても既存ユーザーのパスワードは変わらない。
- 既存ユーザーの復旧は、公開前に管理用のパスワード再設定手順を別途用意する。DBを直接編集しない。

### 500または起動失敗

- RenderのDeployログで、DATABASE_URL、migration、暗号化キーのエラーを確認する。
- Supabaseのプロジェクトが停止していないか確認する。
- SECRET_KEY_BASEとAR_ENCRYPTION_*が前回と同じ値か確認する。値を再生成しない。
- Storageだけが失敗する場合は、S3 endpoint・バケット・Access Key・Secret・regionを確認する。
- `ActiveRecord::ConnectionNotEstablished` の場合は、Session poolerのURI、`sslmode=require`、Supabaseの稼働状態を確認する。
- `ActiveSupport::MessageEncryptor::InvalidMessage` の場合は、暗号化キーを変更していないか確認し、キーを推測して作り直さない。
- `Migrations are pending` の場合は、Renderの起動ログで `db:prepare` が完了しているか確認し、同じDeployを何度も重ねずにmigrationエラーを直す。
- `/up` が200でもログインできない場合は、`APP_EMAIL`、`APP_PASSWORD`、既存ユーザーの有無を確認する。bootstrapは既存ユーザーのパスワードを変更しない。

### Renderの再Deployで添付が消えた

Renderのローカルディスクへ保存している場合は復元できない。添付を使う場合はSupabase Storageを設定し、以後の保存先をRenderの一時ディスクにしない。

## 9. バックアップと復旧

最低限、次の3つを別々に保管する。

- Supabase PostgreSQLのバックアップ
- Supabase Storageのオブジェクト
- SECRET_KEY_BASE、AR_ENCRYPTION_PRIMARY_KEY、AR_ENCRYPTION_DETERMINISTIC_KEY、AR_ENCRYPTION_KEY_DERIVATION_SALT

Free環境では自動バックアップを前提にしない。個人利用中も、実データを登録した日はDBをバックアップし、月1回は新しい環境へ復元できることを確認する。復元テストでは暗号化済みの資料本文、ゲスト名、変更履歴が読めることまで確認する。

### DBバックアップの例

PostgreSQLクライアントを用意した端末で、接続URIを環境変数へ一時的に設定して実行する。URIや出力ファイルをGit管理下へ置かない。

```sh
export WEDDING_DATABASE_URL='SupabaseのSession pooler URI'
pg_dump "$WEDDING_DATABASE_URL" --format=custom --file "wedding-desk-$(date +%Y%m%d).dump"
unset WEDDING_DATABASE_URL
```

復元は本番DBへ直接行わず、別のSupabaseプロジェクトで先に確認する。復元先へ同じ `SECRET_KEY_BASE` と `AR_ENCRYPTION_*` を設定し、`pg_restore --no-owner` 後にログイン、暗号化済み本文、添付へのリンク、ゲスト、変更履歴を確認する。StorageのオブジェクトはDBダンプに含まれないため、Supabase Storage側のバックアップまたはS3互換コピーも別に保管する。

### 復旧後の確認

1. `/up` が200になることを確認する。
2. ログインしてWedding一覧とダッシュボードを開く。
3. 資料本文、画像・PDF、ゲスト名、費用、変更履歴を1件ずつ開く。
4. 2人目のメンバーで同じWeddingへアクセスできることを確認する。
5. 復旧時刻、使用したバックアップ、暗号化キーの世代を運用メモへ残す。

## 10. 無料提供へ進む前の停止条件

次の条件を満たすまで、URLを一般公開しない。

- Render Freeの停止・起動待ちを許容できる個人試験を終えている。
- DB、Storage、暗号化キーの復元テストが完了している。
- Render WebとSolid Queue Workerを分離できる構成を用意している。
- 退会、データ削除、パスワード再設定、問い合わせ先、利用規約、プライバシー説明がある。
- AIを有効にする場合の利用回数・送信同意・費用上限を決めている。

無料で提供する場合でも、利用者の料金が0円であることと、運営費・AI費用・バックアップ費用が0円であることは別に扱う。

## 参考にする公式資料

- [Render Blueprint YAML Reference](https://render.com/docs/blueprint-spec)
- [Render Freeの制約](https://render.com/docs/free)
- [Supabaseの接続方法](https://supabase.com/docs/guides/database/connecting-to-postgres)
- [Supabase StorageのS3認証](https://supabase.com/docs/guides/storage/s3/authentication)
- [Supabaseのバックアップ](https://supabase.com/docs/guides/platform/backups)
