require 'resque/tasks'
require 'yaml'
require './queued_event.rb'
require './sync_database.rb'

task "resque:setup" do
  ENV['QUEUE'] = '*'
  ENV['REDIS_URL'] ||= ENV['RESQUE_REDIS_URL'] || YAML.load(File.read('config/app.yml'))[ENV['RACK_ENV'] || 'development']['resque_redis_url']
end

require 'rspec/core'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end

task :default => :spec
