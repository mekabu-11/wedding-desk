# 検証記録

## 2026-09-08：段階3（画像・PDF添付、出典、横断候補）

- 架空の1px PNGで本文なし資料を保存し、Active Storage添付、Wedding外からのIDOR拒否、認証済みダウンロードの`private, no-store`を確認。
- 空資料、SVG、壊れた画像・PDF、1ファイル上限、10個上限を統合テストで確認。最大値テストは定数を一時的に下げて実データを小さく保ち、実容量を作らない。
- SourceLinkのWedding整合性、資料に属さない添付の拒否、資料削除後のTask保持と削除ChangeEventを確認。既存Taskの出典リンクはmigrationでbackfillする。
- ChangeOperationの型別属性allowlist、未知属性、作成キー依存、根拠引用、添付所属、別Wedding対象、lock_version競合、依存不足、全体rollback、同じChangeSetの再適用を確認。
- Dockerの空テストDBへ全migrationを初回適用し、段階3対象テスト（13 tests / 87 assertions）、全テスト（80 tests / 553 assertions）、`zeitwerk:check`、`git diff --check`を実行し、すべて成功。

外部AIのResponses APIへの実送信はこの検証では行わない。現行のCrossDocumentAiアダプターは未設定時に送信せず失敗状態へ遷移する安全な境界であり、実プロバイダー接続、画像・PDFの外部送信、HEICの成功変換は未検証である。Dockerイメージにはlibvips・libheif・popplerの実行ファイルを含めるが、実在資料での解析精度は保証しない。

## 2026-09-08：段階2（検討・決定、BGM、関連付け、履歴）

- 検討項目・候補・採用／見送り、BGM詳細、費用リンク、タスクリンク、別Wedding拒否を架空データの統合テストで確認。
- 採用候補は1項目1件、採用時の費用選択はトランザクション内で処理し、既存BudgetItemの再利用と3項目から同一BudgetItemへのリンクでも集計を増幅しないことを確認。
- Guest出欠変更、BudgetEstimateRecalculator、採用操作のChangeEventとactor/source、担当の旧値移行互換を確認。
- Dockerで空のテストDBへ全migrationを初回適用し、段階2対象テスト（8 tests / 83 assertions）、全テスト（67 tests / 468 assertions）、`zeitwerk:check`、`git diff --check`を実行し、すべて成功。

## 2026-09-08：段階1（ゲスト・世帯・席次・引き出物・収支基盤）

- 架空データの統合テストを追加：ゲストCRUD、別Weddingのゲスト／BudgetItem IDOR拒否、世帯ごとのご祝儀BudgetItem一意性、出欠・属性変更による概算数量の再計算と確定額固定、区分・引き出物内訳変更による概算再計算、内金・返金・超過表示、引き出物割当の単一BudgetItem、GiftSet内訳の税抜単価計算、属性・検索・二重送信・タブ別表示分離を確認。
- Ruby各モデル・コントローラ・migration・テストの構文確認と`git diff --check`は成功。
- DockerでテストDBを削除・再作成し、全migrationを初回適用したうえで`db:prepare`相当、段階1対象テスト（20 tests / 138 assertions）、全テスト（67 tests / 468 assertions）、`zeitwerk:check`を実行し、すべて成功。`git diff --check`も成功。
- 画面はERBのゲスト4タブ、世帯／卓／ご祝儀区分／引き出物セット／割当、BudgetItem／MoneyMovementの手動CRUDを追加済み。統合テストで各一覧・入力・編集画面のHTMLレンダリングを確認した。Macがロック中のため、CUAブラウザによる実機画面確認は未実施。

## 2026-09-07：2アカウント共有・資料削除後のタスク保持

- Membershipへ既存所有者を移行し、開発DBでusers 1 / weddings 1 / memberships 1、所属のないWedding 0を確認。
- 管理者が設定画面から2人目を追加し、2人目のログインから同じタスクを閲覧できる統合テストを追加。
- メンバーによる3人目追加を拒否し、Weddingを最大2人に制限するテストを追加。
- 資料削除後も承認済みタスクを保持し、Candidate参照を外して削除済み出典を表示するテストを追加。
- Dockerで全39テスト・247 assertions成功。`bin/rails zeitwerk:check`成功。
- 実際の2人目アカウント登録とスマホ実機操作は未実施。

## タスク準備管理の追加検証（2026-09-06）

- Docker内の全テスト：37 tests / 224 assertions / 0 failures / 0 errors。
- 手動追加・出典なしの編集、JSONプレビューと確認後の登録、所有者分離、暗号化、同じ出典の二重登録防止、手修正維持、失敗時の全件ロールバックを検証。
- 開始日・今週への期間重複、日本時間の深夜境界、担当絞り込みと期限超過を検証。
- 実際の45行をDBへ書き込まずImportTasksで検証。
- ブラウザで一時アカウントを使い390px幅の手動追加と1280px幅のプレビュー・登録を確認。横はみ出しなし。確認用データは削除済み。
- Railsのzeitwerk:check成功。利用者の45件の本登録とスマホ実機検証は未実施。

以下は当初MVPの検証記録。

検証日：2026-09-06。ローカルのDocker Desktop / Compose v2.40.3、ARM64。

## 自動テスト

`bin/ci` 成功：**30 tests / 140 assertions / 0 failures / 0 errors / 0 skips**。

確認した項目：

- ログイン、初期設定、登録、承認、タスク編集、削除の一連のフロー
- 他所有者の資料・候補・タスクに対する閲覧・変更・削除・再解析の拒否
- CSRFトークンのない更新リクエストの拒否
- 原文のHTMLエスケープ、no-storeレスポンス
- 原文・候補payloadのDB内暗号化
- 原文の完全一致重複、再解析・再実行による二重生成の防止
- 2スレッドでの同時承認と同時解析開始
- タスクの手修正維持、楽観ロックによる競合検出
- JSON Schema・原文引用・不正な日付・存在しない日付を含む日時の検証
- 日本時間の日付期限の境界
- APIキー未設定、拒否、途中終了、HTTPエラー、最大3回のリトライ
- 有効な候補0件と解析失敗の区別
- 削除済み資料をジョブが復活させないこと

`bin/rails zeitwerk:check` 成功。

## Docker

- `bin/setup` で初回の秘密値生成・イメージ作成・DB初期化・アカウント作成・起動を確認。
- 最終コードで `docker compose build` 成功（productionのassets:precompileを含む）。
- Web・PostgreSQL・Solid Queueワーカーの3サービスを起動。
- ワーカーを停止してサンプルの再解析を投入し、pendingのRunと永続キュー内のJobを確認。ワーカー再起動後にcompletedとなり、候補2件・既存タスク1件を維持。
- `docker compose -f compose.yaml -f compose.production.yaml config --quiet` 成功。
- ActiveRecordのSQLロガーが無効であることをランタイムで確認。

## ブラウザ

一時的なローカル検証アカウントと架空の文章のみで確認。

- ログイン → 結婚式設定 → 概要画面
- サンプル登録 → 実ワーカーの処理 → 根拠付き候補表示
- 候補承認 → タスク一覧への反映 → 状態を進行中へ変更
- 一般の架空メモを登録し、API未設定の案内と原文保存を確認
- デスクトップの概要画面を画像で確認
- 390px幅で概要・候補確認・登録・タスク一覧を確認。ページ幅390px、フォーム部品の横はみ出しなし
- モバイルでも結婚式設定からログアウト可能

検証用アカウント・資料は確認後に削除。初期所有者アカウントは残し、利用者が結婚式設定から開始する。

## 未検証・対象外

- 実際のOpenAI APIへの通信、モデルの利用権限・費用・抽出精度（APIキー未設定）。リクエスト形式とエラー処理はWebMockで検証。
- 実在の結婚式資料20件での精度・確認時間評価
- PDF・画像・見積比較・回答待ち・決定事項（次段階）
- 実環境への公開、TLSプロキシ、バックアップ復元、公開運用の耐負荷検証

今回の完成範囲は「テキスト登録から候補確認・タスク管理まで」。全体MVPの完成とは区別する。
