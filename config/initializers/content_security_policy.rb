Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src :self
  policy.img_src :self, :data
  policy.object_src :none
  policy.script_src :self
  policy.style_src :self
  policy.base_uri :self
  policy.form_action :self
  policy.frame_ancestors :none
end
