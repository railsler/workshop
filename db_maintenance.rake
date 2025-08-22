# frozen_string_literal: true

namespace :db do
  # Usage examples:
  #   rails db:vacuum_reindex                           # Process all tables
  #   rails db:vacuum_reindex[users]                    # Process single table
  #   rails db:vacuum_reindex[users,posts,comments]     # Process multiple tables
  desc "Perform VACUUM and REINDEX for all tables or specified tables"
  task :vacuum_reindex, [:tables] => :environment do |task, args|
    tables_to_process = parse_tables(args[:tables])

    puts "Starting VACUUM ANALYZE..."
    ActiveRecord::Base.connection.execute("VACUUM ANALYZE;")
    puts "VACUUM ANALYZE completed."

    reindex_tables(tables_to_process)
  end

  # Usage examples:
  #   rails db:full_vacuum_reindex                      # Full vacuum all tables (locks database longer)
  #   rails db:full_vacuum_reindex[orders]              # Full vacuum single table
  #   rails db:full_vacuum_reindex[orders,products]     # Full vacuum multiple tables
  desc "Perform full VACUUM and REINDEX for all tables or specified tables"
  task :full_vacuum_reindex, [:tables] => :environment do |task, args|
    tables_to_process = parse_tables(args[:tables])

    puts "Starting VACUUM FULL ANALYZE..."
    ActiveRecord::Base.connection.execute("VACUUM FULL ANALYZE;")
    puts "VACUUM FULL ANALYZE completed."

    reindex_tables(tables_to_process)
  end

  # Usage examples:
  #   rails db:reindex                                  # Reindex all tables
  #   rails db:reindex[users]                          # Reindex single table
  #   rails db:reindex[users,posts,comments]           # Reindex multiple tables
  desc "REINDEX specific tables or all tables"
  task :reindex, [:tables] => :environment do |task, args|
    tables_to_process = parse_tables(args[:tables])
    reindex_tables(tables_to_process)
  end

  # Usage examples:
  #   rails db:vacuum                                   # Vacuum all tables
  #   rails db:vacuum[users]                           # Vacuum single table
  #   rails db:vacuum[users,posts,comments]            # Vacuum multiple tables
  desc "VACUUM specific tables or all tables"
  task :vacuum, [:tables] => :environment do |task, args|
    tables_to_process = parse_tables(args[:tables])
    vacuum_tables(tables_to_process)
  end

  # Usage example:
  #   rails db:show_tables                             # List all available tables with numbers
  desc "Show available tables for maintenance"
  task show_tables: :environment do
    tables = ActiveRecord::Base.connection.tables.sort
    puts "Available tables (#{tables.size}):"
    tables.each_with_index do |table, index|
      puts "  #{index + 1}. #{table}"
    end
  end

  # Usage example:
  #   rails db:interactive_maintenance                 # Start interactive menu for table selection
  #                                                   # Provides options to vacuum/reindex all or selected tables
  desc "Interactive table maintenance"
  task interactive_maintenance: :environment do
    loop do
      puts "\n=== Database Maintenance Menu ==="
      puts "1. Show all tables"
      puts "2. VACUUM all tables"
      puts "3. REINDEX all tables"
      puts "4. VACUUM + REINDEX all tables"
      puts "5. VACUUM selected tables"
      puts "6. REINDEX selected tables"
      puts "7. VACUUM + REINDEX selected tables"
      puts "8. Exit"
      print "\nSelect an option (1-8): "

      choice = STDIN.gets.chomp

      case choice
      when "1"
        Rake::Task["db:show_tables"].invoke
        Rake::Task["db:show_tables"].reenable
      when "2"
        vacuum_tables(all_tables)
      when "3"
        reindex_tables(all_tables)
      when "4"
        ActiveRecord::Base.connection.execute("VACUUM ANALYZE;")
        puts "VACUUM ANALYZE completed."
        reindex_tables(all_tables)
      when "5"
        tables = prompt_for_tables
        vacuum_tables(tables) if tables.any?
      when "6"
        tables = prompt_for_tables
        reindex_tables(tables) if tables.any?
      when "7"
        tables = prompt_for_tables
        if tables.any?
          vacuum_tables(tables)
          reindex_tables(tables)
        end
      when "8"
        puts "Goodbye!"
        break
      else
        puts "Invalid option. Please try again."
      end
    end
  end

  private

  def parse_tables(table_arg)
    return all_tables if table_arg.blank?

    # Handle comma-separated list
    specified_tables = table_arg.split(",").map(&:strip)
    available_tables = all_tables

    # Validate that all specified tables exist
    invalid_tables = specified_tables - available_tables
    if invalid_tables.any?
      puts "Warning: The following tables don't exist and will be skipped:"
      invalid_tables.each { |table| puts "  - #{table}" }
    end

    valid_tables = specified_tables & available_tables
    if valid_tables.empty?
      puts "No valid tables specified. Using all tables."
      return all_tables
    end

    puts "Selected tables: #{valid_tables.join(", ")}"
    valid_tables
  end

  def all_tables
    @all_tables ||= ActiveRecord::Base.connection.tables
  end

  def reindex_tables(tables)
    puts "Starting REINDEX for #{tables.size} table(s)..."

    tables.each_with_index do |table, index|
      print("Reindexing table #{index + 1}/#{tables.size}: #{table}... ")
      start_time = Time.current

      begin
        ActiveRecord::Base.connection.execute("REINDEX TABLE #{ActiveRecord::Base.connection.quote_table_name(table)};")
        elapsed = Time.current - start_time
        puts "completed (#{elapsed.round(2)}s)"
      rescue => e
        puts "failed: #{e.message}"
      end
    end

    puts "REINDEX completed for all selected tables."
  end

  def vacuum_tables(tables)
    puts "Starting VACUUM for #{tables.size} table(s)..."

    tables.each_with_index do |table, index|
      print("Vacuuming table #{index + 1}/#{tables.size}: #{table}... ")
      start_time = Time.current

      begin
        ActiveRecord::Base.connection.execute("VACUUM ANALYZE #{ActiveRecord::Base.connection.quote_table_name(table)};")
        elapsed = Time.current - start_time
        puts "completed (#{elapsed.round(2)}s)"
      rescue => e
        puts "failed: #{e.message}"
      end
    end

    puts "VACUUM completed for all selected tables."
  end

  def prompt_for_tables
    puts "\nAvailable tables:"
    tables = all_tables.sort
    tables.each_with_index do |table, index|
      puts "  #{index + 1}. #{table}"
    end

    puts "\nEnter table selection:"
    puts "  - Numbers (e.g., 1,3,5-8)"
    puts "  - Names (e.g., users,posts,comments)"
    puts "  - 'all' for all tables"
    puts "  - 'exit' to return to menu"

    print("\nSelection: ")
    input = STDIN.gets.chomp.strip

    return [] if input.downcase == "exit"
    return all_tables if input.downcase == "all"

    # Handle numeric ranges and lists (e.g., "1,3,5-8")
    if input.match?(/^[\d,\-\s]+$/)
      selected_indices = []
      input.split(",").each do |part|
        part = part.strip
        if part.include?("-")
          range_start, range_end = part.split("-").map(&:to_i)
          selected_indices.concat((range_start..range_end).to_a)
        else
          selected_indices << part.to_i
        end
      end

      selected_tables = selected_indices.uniq.map { |i| tables[i - 1] }.compact
      puts "Selected: #{selected_tables.join(", ")}" if selected_tables.any?
      return selected_tables
    end

    # Handle table names
    specified_tables = input.split(",").map(&:strip)
    valid_tables = specified_tables & tables

    if valid_tables.empty?
      puts "No valid tables selected."
      return []
    end

    puts "Selected: #{valid_tables.join(", ")}"
    valid_tables
  end
end
