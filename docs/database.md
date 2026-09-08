# データモデルと整合性

## タスク準備管理の追加（2026-09-06）

Taskのcandidate_idはnullable化した。origin=aiでは従来どおり必須（DB制約とモデル検証）、manual/importではAI候補不要。starts_on、source_key、暗号化したsource_detailsを追加。同じWeddingとsource_keyに一意制約を設ける。

TaskImportはWeddingに所属し、暗号化したrowsとdigest、pending/committed、追加/スキップ件数を持つ。確認時はバッチとWeddingをロックし、タスク追加と結果を一括コミットする。ゲスト等の非タスク行は保存しない。本文および元ファイル名等の出典をSQLで直接平文投入しない。

SpreadsheetImportBatch/SpreadsheetImportRowは初回xlsx移行のプレビューと反映履歴を保持する。batchはWedding・ファイルdigest・mapping_version、rowはシート・行・種別・source_key・暗号化した元情報/警告/エラー・反映先を持つ。source_keyの一意性はbatch内に限定し、同じWeddingへの再取込はbatch digestで防ぐ。反映はmaster→世帯→ゲスト→引出物→収支→タスク→BGMの順に一つのtransactionで行い、参照未解決や検証失敗は全体をrollbackする。

xlsxはZIP/XMLとして読み取り、数式・外部リンク・マクロを実行しない。1ファイル25MB、展開後100MB、合計10,000行までで、zip slip・異常圧縮率・壊れた構造を拒否する。実績額や日付不明の金額は確定せず、MoneyMovementも作らない。

以下は既存AIフローの構成。

## 段階1：ゲストと収支の基盤（2026-09-08）

ゲスト領域はすべてWeddingに所属し、`Guest`（個人）を任意の`Household`（世帯）と`SeatingTable`（卓）へ割り当てる。`attendance`は`attending/declined/pending/unanswered`で、招待状態とは別に保存する。`CashGiftRule`は初期提案額だけを持ち、世帯が明示的に登録した時に、世帯ごとに1件の`BudgetItem`（`source_kind=cash_gift`）を作る。

引き出物は`GiftSet`と`GiftSetItem`で設定し、`GiftAssignment`の世帯・セット・数量を手動で確定する。割当を保存すると割当ごとに1件の`BudgetItem`（`source_kind=gift_assignment`）を作る。世帯人数を掛けず、設定価格の変更で確定済み明細を上書きしない。

`GiftSetItem`の単価は税込・税区分不明なら最終価格として扱い、税抜の場合だけ税率と丸め（切捨て・四捨五入・切上げ）を使ってセット合計へ反映する。空の内訳行は保存対象から除外する。

`BudgetItem`は収入／支出、金額、概算／確定、集計対象を1つの正本として保存する。業者・支払先や4種類の金額欄は持たない。`MoneyMovement`はBudgetItemにのみ所属し、支払い・受取・返金・返戻の履歴から未払い・一部・完了・超過を導出する。履歴がある明細は削除できず、同じWedding内の複合インデックス、`lock_version`、同一Weddingの関連検証を備える。お車代の元関連は`travel_guest`／`travel_household`へ分け、曖昧なIDを受け付けない。

出欠・年齢・世帯・席の変更時は、数量計算かつ概算のBudgetItemだけを対象Wedding内で再計算する。確定明細は固定し、再計算は対象scopeの`find_each`で行う。ご祝儀区分の金額変更と引き出物内訳の価格・税率・丸め変更も、紐づく概算明細だけを更新し、既存の確定明細と削除済み区分の明細は保持する。

数量計算で税区分が税抜の場合だけ、明示した`tax_rate`と`rounding`を使って単価×数量へ加算する。税込・不明は加算せず、税率は0〜100の範囲、税抜数量計算では必須とする。直接入力の金額は支払総額として扱う。

## 段階2：検討・決定と関連履歴（2026-09-08）

`PlanningItem`はWedding内の検討項目、`PlanningOption`は候補を表し、候補の状態は下書き・検討中・採用・見送りで管理する。採用はDBの部分一意索引と項目ロック下のトランザクションで1項目1件に制限する。BGMだけ`MusicDetail`を1対1で持ち、希望曲A/B、決定曲、歌手、開始秒、シーン、元表記を保存する。

採用時の費用処理は既存BudgetItemへのリンク、新規支出、追加費用なし、金額未確認のいずれかを必ず選ぶ。`PlanningCostLink`はリンクだけを保存し、同一BudgetItemを複数項目から参照しても収支集計はBudgetItemのIDを1回だけ数える。`TaskPlanningLink`はタスクと検討項目を同一Wedding内で関連付ける。

`ChangeEvent`は採用変更、ゲストの出欠等の手動変更、概算BudgetItemの自動再計算を暗号化したbefore/afterとともに保存する。再計算は対象scopeだけを通常更新し、lock_versionを進め、金額が変わらない場合は履歴を作らない。手動操作はログイン中のactor、自動再計算はactorなしで記録する。

すべての段階1コントローラは`current_wedding`の関連から対象を検索するため、URLへ別WeddingのIDを指定しても404になる。氏名・世帯名・メモ・金額項目名・入出金メモなどはActive Record Encryptionの対象とし、一覧は`includes`または集計クエリと30件ページングで取得する。

PostgreSQLを使用する。通常データとSolid Queueのテーブルは別データベース。同じPostgreSQLコンテナ上で動作する。

```text
User ─1:1─ Membership ─N:1─ Wedding ─1:N─ Document ─1:N─ AnalysisRun
                                  │       └─1:N─ Candidate ─1:0..1─ Task
                                  └──────────────────────────────┘
```

- `users`：メール一意、bcryptパスワードハッシュ。公開登録なし。
- `memberships`：利用者と結婚式を関連付ける。利用者は1結婚式、結婚式は最大2人。owner/editorの役割を持つ。
- `weddings`：2つのログインから共有できる。予算は整数円。
- `documents`：原文、連絡日時、情報元、送受信方向。Wedding＋本文ハッシュが一意。
- `analysis_runs`：解析の状態・使用プロバイダー・モデル/プロンプト/スキーマ版・エラーコード・試行数・実行トークン。
- `candidates`：JSON化した抽出候補と原文引用・文字位置。Document＋fingerprintが一意。引用位置はUnicode文字位置。
- `tasks`：承認時の内容。Candidateごとに最大1件。資料削除後はCandidate参照を外してタスクと暗号化した出典概要を保持する。楽観ロックで古い画面からの上書きを防止。

本文・候補payload・引用・要約・タスク本文をActive Record Encryptionで暗号化する。検索用の本文ハッシュは暗号化本文とは別に保存する。DB volume自体の暗号化はホスト/クラウド側のディスク暗号化に依存する。

## 原子性

候補の承認・却下はDocumentの行ロック内で状態を再確認して反映する。二重承認は既存Taskを返す。タスク保存に失敗した場合は候補の確認状態も変わらない。

解析は長い外部API呼び出し中にDBロックを保持しない。取得時と反映時にDocumentをロックし、最新Runと実行トークンが一致する場合だけ候補を保存する。全候補と要約を同一トランザクションで反映する。

資料削除も同じロックを利用し、実行中ジョブが完了しても削除済み資料を復活させない。

## ジョブ登録と障害

アプリDBとキューDBは別なので、Run作成とジョブ投入は分散トランザクションではない。キュー投入の失敗は失敗状態で表示する。作成後にプロセスが終了して未投入になった場合も、5分後に再試行可能。無制限にジョブを重ねて投入しない。

## 削除

Document削除に伴いRunとCandidateを削除する。承認済みTaskは削除せずCandidate参照を外し、元資料が削除された日時と出典概要を保持する。バックアップや外部AIサービスに既に渡ったデータの削除とは別。運用環境のバックアップ保持期間は配置前に決める。

## 段階3：添付資料と横断候補

Documentは本文なしでも保存でき、Active Storageの`attachments`へ画像またはPDFを複数保持する。許可MIMEはJPEG/PNG/WebP/HEIC/HEIF/PDF、上限は1ファイル20MB・1資料10個・合計50MB・画像40MP・PDF20ページで、MIMEだけでなく画像の実デコードと`pdfinfo`によるページ数・暗号化状態を検証する。SVGと暗号化PDFは拒否する。元ファイルは非公開DiskまたはS3互換ストレージに置き、`DocumentAttachmentsController`がcurrent_weddingと資料の関連を確認してから`private, no-store`で返す。

本番のS3互換設定は`ACTIVE_STORAGE_SERVICE=supabase`と`SUPABASE_STORAGE_ENDPOINT`、`SUPABASE_STORAGE_BUCKET`、`SUPABASE_STORAGE_REGION`、`SUPABASE_STORAGE_ACCESS_KEY_ID`、`SUPABASE_STORAGE_SECRET_ACCESS_KEY`だけで指定する。値が不足している本番ではDocumentの添付バリデーションが保存を拒否する。開発・テストはDiskで、Composeの`storage_data`ボリュームを利用する。

資料の出典はSourceLink（資料、対象型・対象ID、任意の添付・ページ・引用・領域）で管理する。対象型と添付の所属Weddingをモデルで検証し、同じ対象への複数ページの根拠を許可する。資料削除時はSourceLinkと添付を削除するが、登録済みTaskは残し、削除イベントをChangeEventへ記録する。既存Taskの資料由来リンクはmigrationで安全にbackfillする。

横断AIの候補はChangeSetとChangeOperationへ暗号化して保存する。ChangeOperationは型ごとの属性allowlist、enum、最大長、根拠、依存関係、更新時の`expected_lock_version`を検証する。作成した候補への参照は`*_key`を同じChangeSet内で解決し、Wedding ID・利用者ID・版番号は候補属性から指定できない。link操作はSourceLink、PlanningCostLink、TaskPlanningLinkに限定する。反映時は対象レコードをロックしてから版番号を比較し、候補全体を1トランザクションで適用する。競合・根拠不一致・途中失敗は全件を反映しない。同じoperation_keyの再適用は既存結果を返す。

外部AIへ送る処理は「AIで整理」を明示的に選択したジョブだけに限定する。保存・手動確認では送信しない。候補から入出金履歴、採用・確定金額、削除、画像だけの出欠確定は作成できない。
