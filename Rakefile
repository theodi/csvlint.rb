require "bundler/gem_tasks"

$:.unshift File.join(File.dirname(__FILE__), "lib")

require "rubygems"
require "cucumber"
require "cucumber/rake/task"
require "coveralls/rake/task"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)
Coveralls::RakeTask.new
Cucumber::Rake::Task.new(:features) do |t|
  t.cucumber_opts = "features --format pretty"
end

task default: [:spec, :features, "coveralls:push"]
