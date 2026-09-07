class AddWeddingMember
  class Invalid < StandardError; end

  def self.call(wedding:, actor:, email:, password:, password_confirmation:)
    normalized_email = email.to_s.strip.downcase
    raise Invalid, "メールアドレスを入力してください。" if normalized_email.blank?
    raise Invalid, "パスワードは12文字以上で入力してください。" if password.to_s.length < 12
    raise Invalid, "確認用パスワードが一致しません。" unless password == password_confirmation

    wedding.with_lock do
      actor_membership = wedding.memberships.find_by(user_id: actor.id)
      raise Invalid, "共有アカウントを追加できるのは管理者だけです。" unless actor_membership&.owner?
      raise Invalid, "この結婚式にはすでに2人登録されています。" if wedding.memberships.count >= 2
      raise Invalid, "このメールアドレスは登録済みです。" if User.exists?(email: normalized_email)

      user = User.create!(email: normalized_email, password: password, password_confirmation: password_confirmation)
      wedding.memberships.create!(user: user, role: "editor")
    end
  rescue ActiveRecord::RecordInvalid => error
    raise Invalid, error.record.errors.full_messages.to_sentence
  end
end
