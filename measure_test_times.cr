#!/usr/bin/env crystal

# Script to measure individual test execution times
require "file_utils"

# Get all test files
test_files : Array(String) = [] of String
Dir.glob("spec/**/*_spec.cr").each do |file|
  test_files << file
end

puts "Measuring test execution times..."
puts "=" * 50

test_times : Array({String, Time::Span}) = [] of {String, Time::Span}

test_files.each do |file|
  print "Testing #{file}... "

  start_time = Time.monotonic
  result : Process::Status = Process.run("crystal", ["spec", file, "--no-color"], output: Process::Redirect::Close, error: Process::Redirect::Close)
  end_time = Time.monotonic

  elapsed : Time::Span = end_time - start_time
  test_times << {file, elapsed}

  status : String = result.success? ? "PASS" : "FAIL"
  puts "#{elapsed.total_milliseconds.round(1)}ms [#{status}]"
end

puts "\n" + "=" * 50
puts "TOP 10 SLOWEST TESTS:"
puts "=" * 50

test_times.sort_by { |_, time| -time.total_milliseconds }.first(10).each_with_index do |entry, index|
  file, time = entry
  puts "#{index + 1}. #{file.ljust(60)} #{time.total_milliseconds.round(1)}ms"
end

puts "\nTotal files tested: #{test_files.size}"
puts "Total time: #{test_times.sum { |_, time| time.total_milliseconds }.round(1)}ms"
