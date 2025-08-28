# frozen_string_literal: true

# Monkey patch the migration generator to use year folders
Rails.application.config.to_prepare do
  require "rails/generators"
  require "rails/generators/active_record"
  require "rails/generators/active_record/migration/migration_generator"

  ActiveRecord::Generators::MigrationGenerator.class_eval do
    # Override the create_migration_file method
    def create_migration_file
      # Use current year for the folder
      year_folder = Time.current.year.to_s
      dest_dir = Rails.root.join("db", "migrate", year_folder)

      # Create year directory if it doesn't exist
      FileUtils.mkdir_p(dest_dir) unless File.directory?(dest_dir)

      # Create the migration in the year folder
      migration_template(
        "migration.rb",
        File.join("db", "migrate", year_folder, "#{file_name}.rb")
      )
    end
  end
end
