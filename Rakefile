require "rake/testtask"

Rake::TestTask.new(:"test:unit") do |t|
  t.libs = %w[lib test]
  t.test_files = FileList["test/unit/**/*_test.rb"]
  t.verbose = true
end

Rake::TestTask.new(:"test:integration") do |t|
  t.libs = %w[lib test]
  t.test_files = FileList["test/integration/**/*_test.rb"]
  t.verbose = true
end

desc "Run unit and integration tests"
task test: %i[test:unit test:integration]

task default: :test
