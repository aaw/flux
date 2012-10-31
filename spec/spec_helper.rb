require 'resque'
require 'spec_book_loader'

ENV['RACK_ENV'] = 'test'
config = YAML.load(File.read('config/app.yml'))['test']
ENV['REDIS_URL'] = config['app_redis_url']
Resque.redis = Redis.connect(url: config['resque_redis_url'])
Resque.inline = true

bootstrap_book_files

RSpec.configure do |config|
  config.before(:each) do
    Redis.new.flushdb
    Resque.redis.flushdb
  end
end
