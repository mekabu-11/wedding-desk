# リモート公開手順書（GitHub → Render＋Supabase）

この手順は、現在のRailsアプリをGitHubへpushし、Render FreeのWeb ServiceとSupabase FreeのPostgreSQL・Storageで個人用の遠隔環境を作るためのものです。Render Freeは停止・一時ディスク・無バックアップの制約があるため、無料一般公開ではなく個人試験に使います。

## 0. 公開前の前提

- プロジェクトは /Users/zunya/Documents/GitHub/wedding-desk にある。
- 現在のブランチは codex/wedding-management-v1。
- 作業ツリーが空で、bin/verify が成功したリビジョンだけをpushする。
- .env、DBパスワード、Rails暗号化キー、Supabaseの秘密鍵はGitHubへpushしない。
- 既存の本番データがある場合は、先にDB・添付ファイル・暗号化キーをバックアップする。キーを失った状態でDBだけ復元しても暗号化済み本文は読めない。

## 1. ローカルで公開リビジョンを確認する

```sh
cd /Users/zunya/Documents/GitHub/wedding-desk
git status --short
git branch --show-current
bin/verify
```

git status --short に意図しない変更がなく、bin/verify が成功してからpushする。今回の確認結果は次のとおり。

```
122 runs / 985 assertions / 0 failures / 0 errors / 0 skips
```

## 2. GitHubへpushする

まだGitHubリポジトリがなければ、先に非公開リポジトリを作成する。リポジトリ名は例として wedding-desk とする。

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

## 3. Supabaseプロジェクトを作る

1. Supabaseで新しいプロジェクトを作成する。リージョンは利用場所に近いものを選ぶ。
2. Connectから、Renderから到達できる Session pooler のPostgreSQL接続URIを取得する。
3. URIにsslmode=requireが含まれていることを確認する。接続URIはパスワードを含むため、ブラウザ履歴・GitHub Issue・チャットへ貼らない。
4. Storageを使う場合は、非公開バケット（例：wedding-documents）を作成する。
5. StorageのS3互換接続情報から、サーバー専用のAccess KeyとSecretを取得する。Anon keyやService Role keyをブラウザへ渡さない。

### Supabaseで控える値

| 値 | 使い道 |
| --- | --- |
| Session poolerの接続URI | RenderのDATABASE_URL |
| Storage S3 endpoint | SUPABASE_STORAGE_ENDPOINT |
| バケット名 | SUPABASE_STORAGE_BUCKET |
| S3 region | SUPABASE_STORAGE_REGION。通常はus-east-1 |
| S3 access key | SUPABASE_STORAGE_ACCESS_KEY_ID |
| S3 secret | SUPABASE_STORAGE_SECRET_ACCESS_KEY |

## 4. RenderでBlueprintを作る

1. Render Dashboardで New → Blueprint を選ぶ。
2. GitHubリポジトリを接続し、wedding-deskを選ぶ。
3. 個人用試験ならブランチにcodex/wedding-management-v1を指定する。mainへマージして運用する場合はmainを指定する。
4. リポジトリのrender.yamlを読み込ませる。
5. Renderが入力を求める秘密値を設定する。

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

Storage変数は、添付を使わない初回でも後から追加できる。ただし本番で画像・PDFを保存する前には必ず設定する。

RAILS_ENV=production、SOLID_QUEUE_IN_PUMA=true、RAILS_MAX_THREADS=3、WEB_CONCURRENCY=1はrender.yamlに含まれている。FreeプランではSolid Queueを別Workerにせず、Webプロセス内で動かす個人試験構成にしている。

## 5. 初回Deployと起動確認

RenderのDeployを実行する。起動コマンドはbin/render-startで、次の順に実行される。

1. bin/rails db:prepare
2. bin/rails app:bootstrap
3. Rails Web Server起動

Renderのログでmigrationと起動を確認し、次のURLを開く。

```
https://<Renderサービス名>.onrender.com/up
```

200が返ったら、同じドメインのログイン画面でAPP_EMAILとAPP_PASSWORDを使ってログインする。初期アカウントが既に存在する場合、app:bootstrapでパスワードは上書きされない。

## 6. 初回ログイン後の確認順

個人用の架空データまたは少量の実データを使い、次の順で確認する。

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

main運用へ切り替えた後は、Pull Requestをマージして次で更新する。

```sh
git push origin main
```

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

### Renderの再Deployで添付が消えた

Renderのローカルディスクへ保存している場合は復元できない。添付を使う場合はSupabase Storageを設定し、以後の保存先をRenderの一時ディスクにしない。

## 9. バックアップと復旧

最低限、次の3つを別々に保管する。

- Supabase PostgreSQLのバックアップ
- Supabase Storageのオブジェクト
- SECRET_KEY_BASE、AR_ENCRYPTION_PRIMARY_KEY、AR_ENCRYPTION_DETERMINISTIC_KEY、AR_ENCRYPTION_KEY_DERIVATION_SALT

Free環境では自動バックアップを前提にしない。個人利用中も、実データを登録した日はDBをバックアップし、月1回は新しい環境へ復元できることを確認する。復元テストでは暗号化済みの資料本文、ゲスト名、変更履歴が読めることまで確認する。

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
