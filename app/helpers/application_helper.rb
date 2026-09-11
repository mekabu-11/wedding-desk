module ApplicationHelper
  ICON_PATHS = {
    overview: [
      '<circle cx="12" cy="12" r="8.5"/><path d="M8.5 12.5c1.5-1.9 2.7-3 3.5-3s2 .9 3.5 3"/>',
      '<path d="M9.3 14.2c.8 1.2 1.7 1.8 2.7 1.8s1.9-.6 2.7-1.8"/>'
    ],
    documents: [
      '<path d="M6.5 3.5h8l3 3v14h-11z"/><path d="M14.5 3.5v4h3"/>',
      '<path d="M9 12h6M9 15.5h4"/>'
    ],
    tasks: [
      '<rect x="4" y="4" width="16" height="16" rx="2.5"/><path d="m8 9 1.3 1.3L11.5 8"/>',
      '<path d="M13.5 9H17M8 14l1.3 1.3 2.2-2.3M13.5 14H17"/>'
    ],
    guests: [
      '<circle cx="9" cy="8.5" r="3"/><path d="M3.8 19c.4-3.3 2.1-5 5.2-5s4.8 1.7 5.2 5"/>',
      '<path d="M15 6.2a3 3 0 0 1 0 5.7M16.1 14.2c2.3.4 3.6 2 4.1 4.8"/>'
    ],
    money: [
      '<rect x="3.5" y="6" width="17" height="12" rx="2"/><path d="M3.5 9h17M12 11.2v1.6"/>',
      '<circle cx="12" cy="13" r="2.2"/>'
    ],
    planning: [
      '<path d="m12 3 1.7 5.3L19 10l-5.3 1.7L12 17l-1.7-5.3L5 10l5.3-1.7z"/>',
      '<path d="m18.2 15.5.7 2.1 2.1.7-2.1.7-.7 2.1-.7-2.1-2.1-.7 2.1-.7z"/>'
    ],
    help: [
      '<circle cx="12" cy="12" r="8.5"/><path d="M9.8 9.3a2.3 2.3 0 1 1 3.8 1.7c-1.1.8-1.6 1.3-1.6 2.5"/>',
      '<path d="M12 16.8h.01"/>'
    ],
    settings: [
      '<path d="M12 3.8v2.1M12 18.1v2.1M20.2 12h-2.1M5.9 12H3.8M17.8 6.2l-1.5 1.5M7.7 16.3l-1.5 1.5M17.8 17.8l-1.5-1.5M7.7 7.7 6.2 6.2"/>',
      '<circle cx="12" cy="12" r="3.5"/>'
    ],
    rings: [
      '<circle cx="9.2" cy="12" r="5.2"/><circle cx="14.8" cy="12" r="5.2"/>'
    ],
    plus: ['<path d="M12 5v14M5 12h14"/>'],
    document: [
      '<path d="M6.5 3.5h8l3 3v14h-11z"/><path d="M14.5 3.5v4h3M9 12h6M9 15.5h4"/>'
    ],
    budget: [
      '<path d="M4 19.5h16M6.5 17V9.5M11 17V5.5M15.5 17v-4M20 17V7"/>'
    ],
    activity: [
      '<path d="M3.5 13h4l2-6 4.2 11 2.1-5h4.7"/>'
    ]
  }.freeze

  def nav_link(label, path, selected, icon: nil)
    link_to path, class: "nav-link #{'active' if selected}", aria: { current: selected ? "page" : nil } do
      safe_join([ui_icon(icon, size: 18), tag.span(label, class: "nav-label")].compact)
    end
  end

  def ui_icon(name, size: 20, label: nil, class_name: "ui-icon")
    paths = ICON_PATHS.fetch(name.to_sym, ICON_PATHS.fetch(:planning))
    attributes = {
      class: class_name, width: size, height: size, viewBox: "0 0 24 24", fill: "none",
      stroke: "currentColor", "stroke-width": 1.7, "stroke-linecap": "round", "stroke-linejoin": "round"
    }
    if label.present?
      attributes[:role] = "img"
      attributes["aria-label"] = label
    else
      attributes["aria-hidden"] = "true"
    end
    tag.svg(safe_join(paths.map(&:html_safe)), **attributes)
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
