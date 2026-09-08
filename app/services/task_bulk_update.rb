class TaskBulkUpdate
  class Invalid < StandardError; end
  FIELDS = %w[status assignee category].freeze

  def self.apply!(wedding, items, changes, actor: nil)
    new(wedding, items, changes, actor).apply!
  end

  def initialize(wedding, items, changes, actor)
    @wedding, @items, @changes, @actor = wedding, items.to_h, changes.to_h.stringify_keys.slice(*FIELDS).compact_blank, actor
  end

  def apply!
    raise Invalid, "変更項目を1つ以上選択してください。" if @changes.empty?
    raise Invalid, "変更対象がありません。" if @items.empty?
    raise Invalid, "一度に変更できるのは2000件までです。" if @items.size > 2000
    unless @items.keys.all? { |id| id.to_s.match?(/\A\d+\z/) } && @items.values.all? { |version| version.to_s.match?(/\A\d+\z/) }
      raise Invalid, "変更対象の情報が正しくありません。"
    end
    ActiveRecord::Base.transaction do
      @items.sort_by { |id, _| id.to_i }.each do |id, version|
        task = @wedding.tasks.lock.find(id)
        raise ActiveRecord::StaleObjectError.new(task, "bulk update") unless task.lock_version.to_i == version.to_i
        before = task.attributes.slice(*@changes.keys)
        task.update!(@changes)
        after = task.attributes.slice(*@changes.keys)
        ChangeEvent.record!(wedding: @wedding, actor: @actor, target: task, action: "task_bulk_updated",
          before: before.to_json, after: after.to_json, source: "manual") if before != after
      end
    end
  rescue ActiveRecord::RecordNotFound
    raise Invalid, "別のWeddingのタスク、または存在しないタスクです。"
  rescue ActiveRecord::RecordInvalid => error
    raise Invalid, error.record.errors.full_messages.to_sentence
  end
end
