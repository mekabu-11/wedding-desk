class MembershipsController < ApplicationController
  def create
    attributes = params.require(:member).permit(:email, :password, :password_confirmation)
    AddWeddingMember.call(wedding: current_wedding, actor: current_user, **attributes.to_h.symbolize_keys)
    redirect_to edit_wedding_path, notice: "共有アカウントを追加しました。", status: :see_other
  rescue AddWeddingMember::Invalid => error
    redirect_to edit_wedding_path, alert: error.message, status: :see_other
  end
end
