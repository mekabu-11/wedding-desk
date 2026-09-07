class HelpController < ApplicationController
  SCREENSHOTS = %w[login.svg dashboard.svg document-review.svg task-import.svg].freeze

  def show
    page = Rails.root.join("docs", "usage.html").read
    page = page.gsub('src="screenshots/', 'src="/help/screenshots/')
    render html: page.html_safe, layout: false
  end

  def screenshot
    name = "#{params[:name]}.svg"
    return head :not_found unless SCREENSHOTS.include?(name)

    send_file Rails.root.join("docs", "screenshots", name),
      type: "image/svg+xml",
      disposition: "inline"
  end
end
