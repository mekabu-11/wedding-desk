class WeddingCoverPhotosController < ApplicationController
  def show
    cover_photo = current_wedding.cover_photo
    return head :not_found unless cover_photo.attached?

    response.headers["Cache-Control"] = "private, no-store"
    send_data cover_photo.download, filename: cover_photo.filename.to_s, type: cover_photo.content_type,
      disposition: "inline"
  rescue ActiveStorage::FileNotFoundError
    head :not_found
  rescue ActiveStorage::Error, Aws::Errors::ServiceError
    head :service_unavailable
  end
end
