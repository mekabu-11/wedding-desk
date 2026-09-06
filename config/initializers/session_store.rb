Rails.application.config.session_store :cookie_store,
  key: "_wedding_desk", expire_after: 12.hours,
  same_site: :lax, secure: Rails.env.production?, httponly: true
