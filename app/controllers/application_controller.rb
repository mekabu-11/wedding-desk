class ApplicationController < ActionController::Base
  before_action :authenticate
  before_action :require_wedding
  before_action :private_response
  helper_method :current_user, :current_membership, :current_wedding
  private
  def current_user
    return @current_user if defined?(@current_user)
    @current_user = User.find_by(id: session[:user_id]) if session[:expires_at].to_i > Time.current.to_i
  end
  def current_wedding
    current_membership&.wedding
  end
  def current_membership
    return @current_membership if defined?(@current_membership)
    @current_membership = current_user&.membership
  end
  def authenticate
    redirect_to new_session_path unless current_user
  end
  def require_wedding
    redirect_to new_wedding_path unless current_wedding
  end
  def private_response
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "same-origin"
  end
end
