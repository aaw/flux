require 'json'
require 'logger'
require 'redis'
require 'resque'
require 'sinatra'

require './mql_translator.rb'
require './queued_event.rb'
require './sync_database.rb'

config = YAML.load(File.read('config/app.yml'))[ENV['RACK_ENV'] || 'development']
translator = MQLTranslator.load(config)

# Receive an event
get '/event/:event' do
  content_type :json
  if ENV['READ_ONLY'] =~ /1|yes|true/
    halt 501, { error: "This Flux server is read-only" }.to_json
  end
  event_name = params.delete('event')
  Resque.enqueue(QueuedEvent, config, event_name, params)
end

# Run a query
get '/query' do
  content_type :json
  keys = params['keys'] || []
  max_results = params['maxResults'].to_i
  max_results = 50 if max_results < 1 or max_results > 50
  cursor = params['cursor']
  max_score = params['maxScore']
  translator.run_query(keys, max_results, cursor, max_score).to_json
end

# Get a distinct add count
get '/distinct' do
  content_type :json
  options = { op: params['op'], from: params['from'], until: params['until'] }
  { 'count' => translator.get_distinct_count(params['keys'], options) }.to_json
end

# Get a gross add count
get '/gross' do
  content_type :json
  { 'count' => translator.get_gross_count(params['keys']) }.to_json
end

get '/up' do
  content_type :json
  { 'redis' => translator.redis_up? }.to_json
end

if ENV['SYNC_URL']
  # Sync the app database with another redis database
  get '/sync' do
    Resque.enqueue(SyncDatabase, config, ENV['SYNC_URL'])
  end
end

not_found do
  content_type :json
  { 'error' => 'Not Found' }.to_json
end
