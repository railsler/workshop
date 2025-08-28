# frozen_string_literal: true

# Ensure migration paths are set correctly
Rails.application.config.paths["db/migrate"] = Rails.root.glob("db/migrate/*").select do |dir|
  File.directory?(dir) && File.basename(dir) =~ /^\d{4}$/
end.map(&:to_s)
