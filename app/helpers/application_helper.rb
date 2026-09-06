module ApplicationHelper
  def nav_link(label, path, selected)
    link_to label, path, class: "nav-link #{'active' if selected}", aria: { current: selected ? "page" : nil }
  end
  def analysis_error(code)
    {
      "not_configured" => "AI連携が未設定です。資料は保存されています。API設定後に再解析できます。",
      "already_processing" => "解析を実行中です。5分以上結果が出ない場合は再試行できます。",
      "enqueue_failed" => "解析を開始できませんでした。資料は保存されています。再試行してください。",
      "invalid_output" => "解析結果の形式を確認できませんでした。原文は保存されています。再試行してください。",
      "invalid_evidence" => "原文と一致しない根拠が含まれたため、結果を反映しませんでした。",
      "invalid_date" => "解析された期限が不正なため、結果を反映しませんでした。",
      "provider_rejected" => "AIへの接続が拒否されました。APIキーとモデル設定を確認してください。",
      "refused" => "この資料はAIで解析できませんでした。",
      "incomplete_output" => "解析結果が途中で終了しました。資料を分けるか、再試行してください。",
      "rate_limited" => "AIサービスが混雑しています。しばらく待って再試行してください。",
      "provider_unavailable" => "AIサービスへ接続できませんでした。再試行してください。"
    }.fetch(code, "解析を完了できませんでした。資料は保存されています。再試行してください。")
  end
  def document_status(document)
    run = document.latest_run
    return ["未解析", "muted"] unless run
    return ["解析できませんでした", "danger"] if run.status == "failed"
    return ["解析中", "muted"] if run.active?
    count = document.pending_candidates.count
    count.positive? ? ["#{count}件を確認", "amber"] : ["確認済み", "green"]
  end
  def deadline_label(task)
    return task.due_at.in_time_zone.strftime("%Y/%m/%d %H:%M") if task.due_at
    task.due_on&.strftime("%Y/%m/%d") || "期限未設定"
  end
end
