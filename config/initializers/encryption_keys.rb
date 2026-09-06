unless Rails.env.test? || ENV["SECRET_KEY_BASE_DUMMY"]
  required = %w[AR_ENCRYPTION_PRIMARY_KEY AR_ENCRYPTION_DETERMINISTIC_KEY AR_ENCRYPTION_KEY_DERIVATION_SALT]
  if required.any? { |key| ENV[key].blank? }
    raise "Encryption keys are missing. Run bin/setup or set the three AR_ENCRYPTION variables."
  end
end
