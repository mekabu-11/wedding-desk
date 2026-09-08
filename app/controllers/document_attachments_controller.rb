class DocumentAttachmentsController < ApplicationController
  def show
    document = current_wedding.documents.find(params[:document_id])
    attachment = document.attachments.attachments.find(params[:id])
    response.headers["Cache-Control"] = "private, no-store"
    send_data attachment.blob.download, filename: attachment.filename.to_s, type: attachment.content_type,
      disposition: params[:disposition].to_s == "attachment" ? "attachment" : "inline"
  rescue ActiveStorage::FileNotFoundError
    head :not_found
  rescue ActiveStorage::Error, Aws::Errors::ServiceError
    head :service_unavailable
  end
end
