class ExportsController < ApplicationController
  def show
    send_data WeddingCsvExport.call(current_wedding), filename: "wedding-desk-export-#{Date.current.iso8601}.zip", type: "application/zip", disposition: "attachment"
  end
end
