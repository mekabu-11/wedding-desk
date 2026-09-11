# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Propshaft's Rails 8 defaults include stylesheets and builds, but this
# application keeps the small, dependency-free workspace script in the
# conventional javascripts directory. Register it explicitly so the same
# asset lookup works in development and production.
Rails.application.config.assets.paths << Rails.root.join("app/assets/javascripts")
