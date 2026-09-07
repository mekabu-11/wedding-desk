class CandidatesController < ApplicationController
  def update
    @document = current_wedding.documents.find(params[:document_id])
    candidate = @document.candidates.find(params[:id])
    decision = params[:decision]
    return head :bad_request unless %w[accept reject].include?(decision)
    if decision == "accept" && params[:confirmed] != "1"
      return redirect_to @document, alert: "原文と期限・担当を確認してチェックしてください。"
    end
    attributes = decision == "accept" ? params.require(:task).permit(:title, :description, :assignee, :due_on, :due_at, :category).to_h : {}
    attributes["assignee"] = Task.normalize_assignee(attributes["assignee"]) if attributes["assignee"]
    attributes["original_due_text"] = candidate.payload["original_due_text"] if decision == "accept"
    ReviewCandidate.call(candidate, decision: decision, attributes: attributes)
    redirect_to @document, notice: decision == "accept" ? "タスク一覧に反映しました。" : "候補を見送りました。", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    # Do not report the record inspect or source contents in the response/log.
    redirect_to @document, alert: "保存できませんでした。タイトル・期限・担当の入力を確認してください。", status: :see_other
  end
end
