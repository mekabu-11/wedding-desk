# Wedding Desk 引き継ぎメモ

更新日: 2026-09-11

## プロジェクト

- リポジトリ: `/Users/zunya/Documents/GitHub/wedding-desk`
- ブランチ: `codex/wedding-management-v1`
- 実行環境: Docker Compose（Rails / PostgreSQL / Solid Queue）
- 開発URL: `http://127.0.0.1:3210`
- DB・添付ファイル・AIキーなどの秘密情報はこのメモに書かない。

## 直近のコミット

- `41fa395` サイドバーの結婚式情報を整理
- `51183da` タスク一覧の一括変更を上部へ移動
- `453db9b` タスク絞り込みをモーダル化
- `653ba3c` 資料の情報元フィルタを整理
- `e11472e` ログイン画面のサブタイトルを削除
- `69da158` 資料登録を文章・画像・PDF中心に整理

## 確定しているプロダクト方針

- ふたりの2アカウントで同じ結婚式データを共有する。
- タスク・資料・ゲスト・世帯・お金・検討/決定を1つのWedding配下で管理する。
- Excelは初回移行専用。通常運用の入口にはしない。
- 通常運用は、メール本文・文章・写真・PDF・カタログなどを登録し、AIが登録候補を作り、確認後に反映する流れにする。
- 原文・画像・PDFは保存して残す。AI抽出結果には根拠を紐付ける。
- AIは出欠、世帯紐付け、金額、支払状態などを無確認で上書きしない。候補として提示し、利用者が承認する。
- 世帯コードは画面の主要情報にしない。DB上の照合・重複防止用に内部保持する。
- 世帯名は表示し、人数・出欠・ご祝儀・引き出物を中心に見せる。
- タスク一覧は一覧を主役にし、絞り込みはモーダルで開く。行はコンパクトにする。
- ブラックテーマは設定へ置く。サイドバーは折りたたみ可能。

## 現在の主要構造

- `Document`: 原文、添付、情報元、送受信方向、解析履歴の親。
- `AnalysisRun`: AI解析の実行履歴。
- `Candidate`: 資料から抽出したタスク候補。
- `SourceLink`: 資料と登録済みレコードの根拠リンク。
- `ChangeSet` / `ChangeOperation`: 複数領域へのAI反映候補と承認処理。
- `Household` / `Guest`: 世帯と個人ゲスト。`Household#code` は内部照合用として残す。
- `SpreadsheetImport`: Excel初回移行用の別フロー。

## このセッションの未コミット変更

- `app/views/documents/new.html.erb`
  - 「保存してAI整理する →」ボタンが誤って表示値 `1` になっていたため、`button_tag` で表示文言と送信値を分離。
- `test/integration/phase3_test.rb`
  - AI整理ボタンの表示文言・送信値を検証する回帰テストを追加。
- `docs/SESSION_HANDOFF.md`
  - この引き継ぎメモ。

## 次に確認・実装する候補

1. 上記未コミット変更をコミットする。
2. 資料登録画面で、保存ボタンとAI整理ボタンの表示をブラウザ確認する。
3. Excel移行リンクをタスク画面から外し、結婚式設定または初期セットアップ内へ移す。
4. 世帯一覧・世帯編集画面から世帯コードを非表示にする。ただし内部値とCSVバックアップは残す。
5. AIの登録候補で、タスク・決定事項・金額・ゲスト/世帯を同じ確認フローで扱えるか整理する。
6. カタログ画像から商品名・価格・個数・検討/決定状態を抽出する候補型を追加する。

## 検証コマンド

```sh
docker compose run --rm -e RAILS_ENV=test web bin/rails test
docker compose run --rm -e RAILS_ENV=development web bin/rails assets:precompile
docker compose run --rm -e RAILS_ENV=development web sh -c 'rm -f public/assets/.manifest.json'
docker compose restart web
```

全テストは直近時点で `101 runs, 752 assertions, 0 failures, 0 errors, 0 skips`。

