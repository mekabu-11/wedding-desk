class WeddingsController < ApplicationController
  skip_before_action :require_wedding
  def new
    return redirect_to edit_wedding_path if current_wedding
    @wedding = Wedding.new(name: "私たちの結婚式")
  end
  def create
    return redirect_to root_path if current_wedding
    @wedding = Wedding.new(wedding_params)
    if save_wedding_with_owner
      redirect_to root_path, notice: "結婚式の準備をはじめましょう。"
    else
      render :new, status: :unprocessable_entity
    end
  end
  def edit
    @wedding = current_wedding
    redirect_to new_wedding_path unless @wedding
  end
  def update
    @wedding = current_wedding
    return redirect_to new_wedding_path unless @wedding
    if @wedding.update(wedding_params)
      redirect_to root_path, notice: "設定を保存しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end
  private
  def save_wedding_with_owner
    Wedding.transaction do
      @wedding.save!
      @wedding.memberships.create!(user: current_user, role: "owner")
    end
    true
  rescue ActiveRecord::RecordInvalid => error
    @wedding.errors.add(:base, error.record.errors.full_messages.to_sentence) unless error.record == @wedding
    false
  end

  def wedding_params
    params.require(:wedding).permit(:name, :wedding_date, :venue_name, :self_name, :partner_name, :budget_yen)
  end
end
