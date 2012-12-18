require 'json'
require 'resque'
require 'sinatra'

require './mql_translator.rb'
require './queued_event.rb'
require './sync_database.rb'

config = YAML.load(File.read('config/app.yml'))[ENV['RACK_ENV'] || 'development']
translator = MQLTranslator.load(config)

# Events are sent to /event in the body of the POST, in a list of pairs of the form [event, params]
post '/events' do
  content_type :json
  if ENV['READ_ONLY'] =~ /1|yes|true/
    halt 501, { error: "This Flux server is read-only" }.to_json
  end
  
  events = JSON.parse(request.body.read.to_s)
  events.each do |event_name, params|
    Resque.enqueue(QueuedEvent, config, event_name, params)
  end
  nil
end

# Run a query
get '/query' do
  content_type :json
  keys = params['keys'] || []
  max_results = params['maxResults'].to_i
  max_results = 50 if max_results < 1 or max_results > 50
  translator.run_query(keys, max_results, params['cursor'], [params['minScore'], params['maxScore']]).to_json
end

# Get a distinct add count
get '/distinct' do
  content_type :json
  halt 400, { error: "maxScore not supported" }.to_json if params['maxScore']
  { 'count' => translator.get_distinct_count(params['keys'], params['op'], params['minScore']) }.to_json
end

# Get a gross add count
get '/gross' do
  content_type :json
  halt 400, { error: "maxScore not supported" }.to_json if params['maxScore']
  { 'count' => translator.get_gross_count(params['keys'], params['minScore']) }.to_json
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
