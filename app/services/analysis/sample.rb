module Analysis
  class Sample
    TEXT = <<~TEXT.freeze
      2026年9月6日 式場からの連絡（架空のサンプル）

      お打ち合わせありがとうございました。
      BGMリストを2026年9月20日までにご提出ください。担当はお二人です。
      装花の色味について、2026年9月22日までにご返信ください。
      母親衣装はレンタルを検討中です。まだ確定していません。
    TEXT
    def call(document)
      raise Error.new("invalid_sample") unless document.sample? && document.original_text == TEXT.strip
      {
        "summary" => "BGMリストの提出と装花の色味について返信が必要です。母親衣装は検討中です。",
        "category" => "venue",
        "tasks" => [
          { "title" => "BGMリストを提出する", "description" => "式場へBGMリストを提出する。", "assignee" => "both", "due_on" => "2026-09-20", "due_at" => nil, "original_due_text" => "2026年9月20日まで", "category" => "music", "uncertainty_reasons" => [], "quote" => "BGMリストを2026年9月20日までにご提出ください。担当はお二人です。" },
          { "title" => "装花の色味について返信する", "description" => "希望する色味を確認して式場へ返信する。", "assignee" => "unknown", "due_on" => "2026-09-22", "due_at" => nil, "original_due_text" => "2026年9月22日まで", "category" => "flower", "uncertainty_reasons" => ["担当は原文に記載されていません"], "quote" => "装花の色味について、2026年9月22日までにご返信ください。" }
        ]
      }
    end
  end
end
