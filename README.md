# Wedding Desk

結婚式の連絡を保存し、根拠付きのタスク候補を確認して、やること一覧へ反映するRailsアプリです。

**実行環境はDockerのみです。ホストへのRuby・PostgreSQL・Node.jsのインストールは不要です。**

## 今回の実装範囲

- 招待制ログイン（公開登録なし）、2アカウントで同じ結婚式を共有、結婚式設定
- メール・LINE・メモのテキスト登録（30,000文字まで）
- Solid Queueの永続ワーカーによる非同期解析
- OpenAI Responses APIの構造化出力、JSON Schema・引用・日付の検証
- 原文と候補の比較、編集して承認、見送り
- タスクの期限・担当・状態の編集、根拠へ戻るリンク
- 手動タスク追加、開始日、担当・今週・期限超過の絞り込み
- Excelから抽出した移行用JSONのタスク取り込み（担当確認・出典保持・二重登録防止）
- 二重登録・二重承認防止、手修正保護、再試行、資料削除後も登録済みタスクを保持
- 暗号化された本文・候補・要約・タスク、認可とログの機密情報抑制
- ゲスト配下の個人・世帯・席次・引き出物の手動CRUD、ご祝儀区分、引き出物割当
- 金額1つ＋概算／確定のBudgetItem、MoneyMovementから導出する支払状況と入出金履歴
- 検討・決定の項目／候補／BGM詳細、採用時の費用リンクとタスクリンク、変更履歴
- 架空のサンプルによる操作体験（AIの代替や実データの解析ではありません）

PDF・画像、見積比較、回答待ち、xlsx全体移行は次段階です。検討・決定とBGM、採用費用の関連付けは画面から手動操作できます。

## 起動

Docker Desktopを起動してから、プロジェクトディレクトリで次を実行します。

```sh
bin/setup
```

初回に `.env` を自動生成し、ランダムなログインパスワード・暗号化鍵・DBパスワードを保存します。既存の `.env` は上書きしません。Web・ワーカー・PostgreSQLをビルドしてDBを準備し、初期アカウントを作成します。

既存のPostgreSQLボリュームがある場合も、`bin/setup` が `.env` のDBパスワードをDBユーザーへ同期してから準備処理を行います。DBボリューム内のデータは削除しません。

- URL：http://localhost:3210
- 初期メール：`owner@example.test`（`.env` の `APP_EMAIL`）
- 初期パスワード：`.env` の `APP_PASSWORD`

メールとパスワードでログインし、結婚式の基本情報を入力してください。API設定前でも「サンプルで試す」で候補の確認からタスクへの反映まで体験できます。

結婚式を作成した管理者は「結婚式の設定 → ふたりで共有」から、2人目のメールアドレスと12文字以上の初期パスワードを登録できます。2人目は同じログイン画面から入り、同じタスク・資料・設定を利用できます。公開登録や招待メール送信はありません。

`.env.example` をそのまま `.env` にコピーすると秘密値が空欄のため起動しません。初回は `bin/setup` に生成させてください。既存DBを利用中に暗号化鍵を作り直すと、保存データを復号できなくなります。

```sh
# 次回以降の起動
 docker compose up -d
# 状態確認
 docker compose ps
# 停止（DBはnamed volumeに残る）
 docker compose stop
# コンテナの削除（DB volumeは残る）
 docker compose down
```

ポートを変更する場合は `.env` の `APP_PORT` を変更して `docker compose up -d`。DBのポートはホストに公開していません。ほかのComposeプロジェクトと分離されています。

## 実資料をAI解析する

タスク移行の使い方は `docs/task-import.md` を参照してください。「やること → データを取り込む」から準備済みのJSONを選び、担当を割り当てて登録します。段階1のゲスト・収支は画面から手動登録できます。BGMと.xlsx直接アップロードは未対応です。

`.env` に次を設定します。

```dotenv
OPENAI_API_KEY=利用者のAPIキー
LLM_MODEL=Responses_APIとstrict_JSON_Schemaに対応する利用可能なモデルID
```

```sh
docker compose up -d --force-recreate web worker
```

モデルはコード内で固定していません。本文・資料の連絡日時・方向・担当表示名をOpenAIへ送信します。`store: false` を指定しますが、これは提供元の全ログや保持期間がゼロになる保証ではありません。提供元のデータ取り扱いを確認して利用してください。

APIが未設定の一般資料は保存後に「AI連携が未設定」と表示されます。設定後に「再解析する」で再開できます。勝手にサンプル結果へ置き換えることはありません。

## テストと検証

```sh
docker compose run --rm -e RAILS_ENV=test web bin/rails db:prepare
docker compose run --rm -e RAILS_ENV=test web bin/rails test
docker compose exec web bin/rails zeitwerk:check
```

`db:prepare` と `test` は別のプロセスで実行してください。テスト用DBは開発DBから分離しています。外部AI通信はWebMockで禁止・代替し、費用と実データ送信を発生させません。

検証結果と未検証事項は `docs/verification.md` を参照してください。

## 依存関係

Ruby 3.4 / Rails 8.1.3.1 / PostgreSQL 17 / Solid Queue。Gemの解決結果は `Gemfile.lock` に固定しています。UIはRailsビューと小さなCSSで実装し、今回の範囲ではNode.jsビルド・Tailwind・React・JavaScript実行依存を追加していません。

## ドキュメント

- `docs/wedding-preparation-design.md`：実際のExcelに基づく準備管理への拡張設計・データ移行方針（追加機能は未実装）
- `docs/requirements.md`：今回の範囲と次段階
- `docs/database.md`：保存モデルと整合性
- `docs/wedding-desk-design-v1.md`：段階1以降を含む承認済み設計
- `docs/ai-analysis.md`：AI処理とエラー時の挙動
- `docs/deployment.md`：Dockerによる配置・運用手順
- `docs/verification.md`：検証結果
- `wedding_secretary_mvp_spec_v0.2.md`：MVP全体の仕様
