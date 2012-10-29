require 'resque/tasks'
require 'resque_scheduler/tasks'
require './queued_event.rb'
require './sync_database.rb'

task "resque:setup" do
  require 'resque'
  require 'resque_scheduler'
  require 'resque/scheduler'

  ENV['QUEUE'] = '*'
  ENV['INTERVAL'] = '0.2'
  config = YAML.load(File.read('config/app.yml'))
  ENV['REDIS_URL'] ||= ENV['RESQUE_REDIS_URL'] || config[ENV['RACK_ENV'] || 'development']['resque_redis_url']
  ENV['APP_REDIS_URL'] ||= config[ENV['RACK_ENV'] || 'development']['app_redis_url']

  Resque.schedule = YAML.load_file('config/resque_schedule.yml')

  require './time_range_rollup.rb'
end
