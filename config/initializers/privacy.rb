Rails.application.config.filter_parameters += [
  :password, :password_confirmation, :email, :name, :self_name, :partner_name,
  :title, :description, :original_text, :summary, :payload, :quote, :evidence,
  :sender, :recipient, :api_key, :token, :original_due_text
]
# SQL bind values and framework exception pages must not expose diary/document text.
ActiveSupport.on_load(:active_record) { self.logger = nil }
Rails.application.config.active_record.attributes_for_inspect = [:id]
Rails.application.config.active_job.log_arguments = false
