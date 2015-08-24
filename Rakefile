
require 'bundler'
require 'rake/testtask'
require 'rubocop/rake_task'
Bundler::GemHelper.install_tasks

Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.test_files = FileList['test/*.rb']
  test.verbose = true
end

namespace :style do
  desc 'Run Ruby style checks'
  RuboCop::RakeTask.new(:ruby)
end

desc 'Run all style checks'
task style: ['style:ruby']

task default: ['build']
