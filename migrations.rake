# frozen_string_literal: true

# lib/tasks/migrations.rake

namespace :migrations do
  desc "Organize migrations into year-based subdirectories"
  task organize_by_year: :environment do
    migrate_path = Rails.root.join("db/migrate")

    unless Dir.exist?(migrate_path)
      puts "Migration directory doesn't exist: #{migrate_path}"
      exit 1
    end

    # Get all migration files
    migration_files = Dir.glob(File.join(migrate_path, "*.rb"))

    if migration_files.empty?
      puts "No migration files found in #{migrate_path}"
      exit 0
    end

    organized_count = 0
    errors = []

    migration_files.each do |file_path|
      filename = File.basename(file_path)

      # Extract year from migration timestamp (format: YYYYMMDDHHMMSS_migration_name.rb)
      if filename =~ /^(\d{4})\d{10}_.*\.rb$/
        year = Regexp.last_match(1)
        year_dir = File.join(migrate_path, year)

        begin
          # Create year directory if it doesn't exist
          FileUtils.mkdir_p(year_dir) unless Dir.exist?(year_dir)

          # Move the file to the year directory
          new_path = File.join(year_dir, filename)

          if File.exist?(new_path)
            puts "⚠️  File already exists in destination: #{filename} -> #{year}/"
          else
            FileUtils.mv(file_path, new_path)
            puts "✓ Moved: #{filename} -> #{year}/"
            organized_count += 1
          end
        rescue => e
          errors << "Error moving #{filename}: #{e.message}"
        end
      else
        puts "⚠️  Skipping invalid migration filename: #{filename}"
      end
    end

    puts "\n" + "=" * 50
    puts "Organization complete!"
    puts "Files organized: #{organized_count}"

    if errors.any?
      puts "\nErrors encountered:"
      errors.each { |error| puts "  - #{error}" }
    end

    # Show the new structure
    puts "\nCurrent migration structure:"
    Dir.glob(File.join(migrate_path, "*")).sort.each do |path|
      next unless File.directory?(path)

      year = File.basename(path)
      count = Dir.glob(File.join(path, "*.rb")).count
      puts "  📁 #{year}/ (#{count} migration#{"s" if count != 1})"
    end
  end

  desc "Restore migrations from year subdirectories back to main migrate folder"
  task restore_from_years: :environment do
    migrate_path = Rails.root.join("db/migrate")
    restored_count = 0
    errors = []

    # Find all year directories
    year_dirs = Dir.glob(File.join(migrate_path, "*")).select do |path|
      File.directory?(path) && File.basename(path) =~ /^\d{4}$/
    end

    if year_dirs.empty?
      puts "No year directories found in #{migrate_path}"
      exit 0
    end

    year_dirs.each do |year_dir|
      year = File.basename(year_dir)
      migration_files = Dir.glob(File.join(year_dir, "*.rb"))

      migration_files.each do |file_path|
        filename = File.basename(file_path)
        new_path = File.join(migrate_path, filename)

        begin
          if File.exist?(new_path)
            puts "⚠️  File already exists in main directory: #{filename}"
          else
            FileUtils.mv(file_path, new_path)
            puts "✓ Restored: #{year}/#{filename} -> main directory"
            restored_count += 1
          end
        rescue => e
          errors << "Error restoring #{filename}: #{e.message}"
        end
      end

      # Remove empty year directory
      if Dir.empty?(year_dir)
        FileUtils.rmdir(year_dir)
        puts "📁 Removed empty directory: #{year}/"
      end
    end

    puts "\n" + "=" * 50
    puts "Restoration complete!"
    puts "Files restored: #{restored_count}"

    if errors.any?
      puts "\nErrors encountered:"
      errors.each { |error| puts "  - #{error}" }
    end
  end

  desc "Show migration distribution by year without moving files"
  task preview_by_year: :environment do
    migrate_path = Rails.root.join("db/migrate")

    unless Dir.exist?(migrate_path)
      puts "Migration directory doesn't exist: #{migrate_path}"
      exit 1
    end

    # Get all migration files (both in main dir and subdirs)
    all_files = Dir.glob(File.join(migrate_path, "**", "*.rb"))

    if all_files.empty?
      puts "No migration files found"
      exit 0
    end

    # Group by year
    migrations_by_year = Hash.new { |h, k| h[k] = [] }

    all_files.each do |file_path|
      filename = File.basename(file_path)

      next unless filename =~ /^(\d{4})\d{10}_.*\.rb$/

      year = Regexp.last_match(1)
      relative_path = file_path.sub(migrate_path.to_s + "/", "")
      migrations_by_year[year] << relative_path
    end

    puts "Migration distribution by year:"
    puts "=" * 50

    migrations_by_year.sort.each do |year, files|
      puts "\n#{year} (#{files.count} migration#{"s" if files.count != 1}):"
      files.sort.each do |file|
        puts "  - #{file}"
      end
    end

    puts "\n" + "=" * 50
    puts "Total migrations: #{all_files.count}"
    puts "Years covered: #{migrations_by_year.keys.sort.first} - #{migrations_by_year.keys.sort.last}"
  end

  desc "Validate migration file naming and structure"
  task validate: :environment do
    migrate_path = Rails.root.join("db/migrate")

    unless Dir.exist?(migrate_path)
      puts "Migration directory doesn't exist: #{migrate_path}"
      exit 1
    end

    all_files = Dir.glob(File.join(migrate_path, "**", "*.rb"))
    issues = []
    valid_count = 0

    puts "Validating migration files..."
    puts "=" * 50

    all_files.each do |file_path|
      filename = File.basename(file_path)
      relative_path = file_path.sub(migrate_path.to_s + "/", "")

      # Check filename format
      if filename =~ /^(\d{14})_(.+)\.rb$/
        timestamp = Regexp.last_match(1)
        year = timestamp[0..3]

        # Check if file is in correct year directory
        dir_path = File.dirname(relative_path)
        if dir_path != "." && dir_path != year
          issues << "File in wrong year directory: #{relative_path} (should be in #{year}/)"
        else
          valid_count += 1
        end
      else
        issues << "Invalid migration filename format: #{relative_path}"
      end
    end

    if issues.empty?
      puts "✅ All #{valid_count} migrations are valid!"
    else
      puts "⚠️  Found #{issues.count} issue#{"s" if issues.count != 1}:"
      issues.each { |issue| puts "  - #{issue}" }
      puts "\n✓ Valid migrations: #{valid_count}"
    end
  end
end
