namespace :app do
  desc "Create the private owner account; never reset an existing password"
  task bootstrap: :environment do
    email = ENV.fetch("APP_EMAIL").strip.downcase
    password = ENV.fetch("APP_PASSWORD")
    abort "APP_PASSWORD must have at least 12 characters" if password.length < 12
    if User.exists?(email: email)
      puts "Owner account already exists (password unchanged)."
    else
      User.create!(email: email, password: password)
      puts "Owner account created. Credentials are in your local .env file."
    end
  end
end
