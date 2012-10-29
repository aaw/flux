require 'hyperloglog-redis'
require 'logger'
require 'redis'

class TimeRangeRollup
  @queue = :rollup
  @log = Logger.new(STDOUT)
  @log.level = Logger::INFO

  # Every minute, for all keys of the form flux:time-rollup:current:*, merge
  # flux:time-rollup:current:id -> flux:time-rollup:1:id:#{Time.now.to_i - 60}:#{Time.now}

  # Assuming that this isn't called more than once a second, since that would
  # result in data getting overwritten. In practice, it's scheduled by 
  # resque-scheduler to run every minute.

  def self.perform
    redis = Redis.connect(url: ENV['APP_REDIS_URL'])
    counter = HyperLogLog.new(redis)

    @log.info { "Executing a roll-up" }

    # Move current keys to stage 1
    current_stage = 1
    rollup_time = Time.now.to_i
    redis.keys('flux:time-rollup:current:*').each do |key|
      rollup_key = "flux:time-rollup:#{current_stage}:#{key.split(':').last}:#{rollup_time - 60}:#{rollup_time}"
      redis.rename(key, rollup_key)
      @log.info { "Rolling #{key} into #{rollup_key}" }
    end

    while true
      keys_to_roll = redis.keys("flux:time-rollup:#{current_stage}:*")
                          .group_by{ |k| k.split(':')[-3] }
                          .select{ |bucket, group| group.length > 1 }

      break if keys_to_roll.empty?

      keys_to_roll.each do |bucket, keys|
        to_roll = keys.sort.take(2)
        min_rollup_time = to_roll.sort_by{ |k| k[-2].to_i }.first.split(':')[-2]
        max_rollup_time = to_roll.sort_by{ |k| k[-1].to_i }.last.split(':')[-1]
        new_key = "flux:time-rollup:#{current_stage * 2}:#{bucket}:#{min_rollup_time}:#{max_rollup_time}"
        @log.info { "Rolling #{to_roll.first} and #{to_roll.last} into #{new_key}" }
        counter.union_store(new_key, *to_roll)
        to_roll.each { |key| @redis.del(key) }
      end

      current_stage *= 2
    end

    @log.info { "Done with roll-up" }
  end
end
