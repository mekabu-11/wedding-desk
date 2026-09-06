# AI解析

## 入出力

`Analysis::OpenaiClient` がResponses APIを呼ぶ。モデルは `LLM_MODEL`、鍵は `OPENAI_API_KEY`。外部ツール呼び出し権限なし。資料に書かれた命令は入力データとして扱う。

入力：対象原文、情報元、送受信方向、連絡日時、Asia/Tokyo、本人とパートナーの表示名。

出力：要約・カテゴリ・タスク候補。スキーマは `config/analysis_schema.json`、プロンプトは `Analysis::OpenaiClient::PROMPT`。

各タスク候補はtitle、description、assignee、due_on、due_at、original_due_text、category、uncertainty_reasons、quoteを持つ。日付・担当が不明なら空欄・unknownを使い、完了済み依頼や相手の回答待ちを自分の新規タスクにしないよう指示する。

## 検証

1. HTTPステータス・拒否・途中終了を判定する。
2. JSON Schemaへ適合するか検証する。
3. quoteと期限原文が対象本文に存在するか検証する。
4. 日付・日時の形式と実在性、両期限の排他性を検証する。
5. 候補を保存し、利用者の確認を待つ。

引用が一致しても推論が正しい保証にはならない。候補の意味的正確さは実資料で評価する。根拠のない候補を検出した場合、同じRunの一部だけを成功扱いにせず候補一式を反映しない。

## リトライと秘密情報

一時障害・429は30秒待ち、最大3回。認証エラー・不正な結果・拒否は自動再試行せず画面に理由を表示する。接続10秒、読み取り90秒、書き込み15秒のタイムアウトを設定する。

原文・プロバイダーの応答本文・APIキーはログに出さない。予期しない例外も型名とRun IDだけを記録する。ジョブ引数はRun IDだけ。

## サンプル

`Analysis::Sample` は固定の架空メールだけを対象とする。原文とsampleフラグを検証し、一般資料を偽のAI結果で処理しない。画面にも固定例であることを表示する。通常のワーカーを経由するため、キューから承認までの操作をAPIキーなしで確認できる。

## 公式仕様

- [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)：`text.format`のstrict JSON Schema。
- [APIのデータ取り扱い](https://developers.openai.com/api/docs/guides/your-data)：利用するアカウントと設定に応じて保持条件を確認する。

`store: false` はResponsesの保存を無効化する指定であり、全種類のログ保持や監視を無効化する意味ではない。
