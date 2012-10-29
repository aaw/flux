require 'cartesian-product'
require 'hyperloglog-redis'
require 'json'
require 'logger'
require 'redis'
require 'murmurhash3'

class MQLTranslator

  def initialize(redis, counter, schema, options={})
    @redis = redis
    @counter = counter
    @schema = schema
    @op_counter_lower_bits = 0
    @rollup_modulus = 2 ** [(options[:rollup_modulus_bitwidth] || 0), 10].min
    if options[:logger]
      @log = options[:logger]
    else
      @log = Logger.new(STDOUT)
      @log.level = Logger::FATAL
    end
  end

  def self.load(settings)
    schema = JSON.parse(File.open('config/schema.json').read)
    log = Logger.new(STDOUT)
    log.level = Logger.const_get settings['log_level']
    app_redis = Redis.connect(url: (ENV['APP_REDIS_URL'] || settings['app_redis_url']))
    resque_redis = Redis.connect(url: (ENV['RESQUE_REDIS_URL'] || settings['resque_redis_url']))
    Resque.redis = resque_redis
    counter = HyperLogLog.new(app_redis, settings['hyperloglog_precision'])
    MQLTranslator.new(app_redis, counter, schema, {logger: log})
  end

  def process_event(event_name, args)
    @schema.each_pair do |event_filter, handlers|
      next unless event_name.start_with?(event_filter)
      handlers.each do |handler|
        begin
          execute_handler(handler, event_name, args)
        rescue Exception => e
          throw unless e.message =~ /^Undefined attribute/
        end
      end
    end

    if args['@targets']
      # Explicitly enumerate accepted runtime args, to be safe
      runtime_args = {
        'targets'         => args['@targets'],
        'add'             => args['@add'],
        'remove'          => args['@remove'],
        'maxStoredValues' => (args['@maxStoredValues'].to_i if args['@maxStoredValues'])
      }
      execute_handler(runtime_args, event_name, args)
    end
  end

  def execute_handler(handler, event_name, args)
    sorted_sets = resolve_keys(handler['targets'], event_name, args)
    sorted_sets.each_with_index do |set_name_components, i|
      set_name = set_name_components.join(':')
      value_definition = handler['add'] || handler['remove']
      raise "Must specify either an add or remove handler" unless value_definition
      value = resolve_id(value_definition, event_name, args)
      store_values = handler['maxStoredValues'] != 0
      timestamp = (Integer(args['@score']) rescue nil)
      if handler['add']
        if store_values
          @log.debug { "Appending '#{value}' to #{set_name}" }
          @redis.zadd("flux:set:#{set_name}", op_counter(timestamp, value), value)
        end
        if handler['maxStoredValues'] && store_values
          @log.debug { "Trimming the stored set to hold at most #{handler['maxStoredValues']} values" }
          @redis.zremrangebyrank(set_name, 0, -1 - handler['maxStoredValues'])
        end
        value_id = "#{set_name}:#{value}"
        rollup_bucket = rollup_id(set_name)
        @log.debug { "Incrementing distinct count for #{set_name}" }
        @counter.add("flux:distinct:#{set_name}", value_id)
        @log.debug { "Incrementing gross count for #{set_name}" }
        @counter.add("flux:gross:#{set_name}", op_counter(timestamp, value_id).to_s)
        @log.debug { "Incrementing current time rollup counter #{rollup_bucket}" }
        @counter.add("flux:time-rollup:current:#{rollup_bucket}", value_id)
      elsif handler['remove']
        @log.debug { "Removing '#{value}' from #{set_name}" }
        @redis.zrem("flux:set:#{set_name}", value)
      end
    end
  end

  def get_distinct_count(keys, options)
    op = options[:op] || 'union'
    from_time = options[:from].to_i if options[:from]
    until_time = options[:until].to_i if options[:until]
    namespaced_keys = keys.map { |key| "flux:distinct:#{key}" }

    if from_time || until_time
      temp_key = "flux:temp:#{SecureRandom.uuid}"
      union_keys = keys.map{ |key| resolve_time_range_to_keys(key, from_time, until_time) }.flatten if from_time || until_time
      @log.debug { "Storing union of keys #{union_keys} in #{temp_key} for time range comparison" }
      @counter.union_store(temp_key, *union_keys)
      retval = 0
      if op.to_s == 'union'
        temp_union = "flux:temp:#{SecureRandom.uuid}"
        unioned_key = @counter.union_store(temp_union, *namespaced_keys)
        retval = @counter.intersection(temp_key, temp_union)
        @redis.del(temp_union)
      elsif op.to_s == 'intersection'
        retval = @counter.intersection(temp_key, *namespaced_keys)
      end
      @redis.del(temp_key)
      return retval
    end

    if op.to_s == 'union'
      @counter.union(*namespaced_keys)
    elsif op.to_s == 'intersection'
      @counter.intersection(*namespaced_keys)
    end
  end

  def get_gross_count(keys)
    namespaced_keys = keys.map { |key| "flux:gross:#{key}" }
    if namespaced_keys.size == 0
      0
    elsif namespaced_keys.size == 1
      @counter.count(namespaced_keys[0])
    else
      @counter.union(*namespaced_keys)
    end
  end

  def op_counter(score = nil, value = nil)
    if score && score.to_i >= 0 && score.to_i < 2147483648 # 2**31
      # Client has provided their own score; use it. Append a hash of the
      # value to break ties.
      value_bits = value ? MurmurHash3::V32.murmur3_32_str_hash(value) % 1048576 : 0
      (score.to_i << 20) + value_bits
    else
      # Client did not provide a score, generate one from the current time,
      # to the millisecond, plus the value of a rotating 10-bit counter.
      seconds_since_the_epoch = Time.now.to_f
      milliseconds_part = (seconds_since_the_epoch * 1000).to_i % 1000
      @op_counter_lower_bits = (@op_counter_lower_bits + 1) % 1024
      (seconds_since_the_epoch.to_i << 20) + (milliseconds_part << 10) + @op_counter_lower_bits
    end
  end

  def run_query(keys, max_results, cursor, max_score = nil)
    if max_score && !max_score.empty?
      start = op_counter(max_score.to_i + 1)
      start = [ start, cursor.to_i ].min if cursor && !cursor.empty?
    elsif cursor && !cursor.empty?
      start = cursor
    else
      start = "inf"
    end

    all_results = keys.map { |key| @redis.zrevrangebyscore("flux:set:#{key}", "(#{start}", "-inf", { withscores: true, limit: [0, max_results] }).reverse }
    raw_results = max_results.times.map { (all_results.max_by { |results| (results.last || [nil,-1]).last } || []).pop }.compact

    results = raw_results.map { |result| result.first }.uniq
    if raw_results.length < max_results
      { 'results' => results }
    else
      { 'results' => results, 'next' => raw_results.last.last }
    end
  end

  def resolve_id(id, event_name, args)
    if id.start_with?('@')
      return args[id] if args[id]
      case id[1..-1]
      when 'eventName'
        event_name
      when 'uniqueId'
        op_counter.to_s
      else
        raise "Unknown identifier #{id}"
      end
    elsif id.start_with?("'") and id.end_with?("'")
      id[1...-1]
    else
      value = args[id]
      raise "Undefined attribute #{id}" unless value
      value
    end
  end

  def resolve_keys(targets, event_name, args)
    multiplicands = targets.map do |target|
      components = target.split('.').reverse
      entries = components.pop[1...-1].split(',').map{ |x| resolve_id(x.strip, event_name, args) }
      while !components.empty? do
        key = components.pop
        entries = entries.map do |entry|
          sorted_set = "#{entry}:#{key}"
          components.empty? ? sorted_set : @redis.zrevrange("flux:set:#{sorted_set}", 0, -1)
        end.flatten
      end
      entries
    end
    CartesianProduct.new(*multiplicands)
  end
  
  def resolve_time_range_to_keys(key, time_from, time_until)
    time_from ||= 0
    time_until ||= Time.now.to_i
    bucket_id = rollup_id(key)
    candidates = []
    candidates << "flux:time-rollup:current:#{bucket_id}" if (Time.now.to_i - time_until) <= 60
    stage = 1
    while true
      current_candidates = @redis.keys("flux:time-rollup:#{stage}:#{bucket_id}:*")
      current_candidates.select! do |key|
        start_time, end_time = key.split(':').last(2).map{ |x| x.to_i }
        (start_time <= time_from && time_from <= end_time) || (start_time <= time_until && time_until <= end_time)
      end
      break if current_candidates.empty?
      candidates += current_candidates
      stage *= 2
    end
    candidates.sort_by{ |k| k.split(':').last.to_i }
  end
    
  def rollup_id(set_name)
    MurmurHash3::V32.murmur3_32_str_hash(set_name) % @rollup_modulus
  end

  def redis_up?
    time = Time.now.to_i
    @redis.set("flux:system:pingtime", time) == "OK"
  end

end
