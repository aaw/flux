require 'hyperloglog-redis'
require 'logger'
require 'redis'

# This task rolls up HyperLogLog counters of the form flux:time-rollup:* so 
# that there are only O(log T) of these counters for any time range of T
# minutes, decreasing in accuracy as you go back in time.
#
# Every operation from Flux is counted in the key flux:time-rollup:current:X,
# where X is bucket id. Every minute, resque-scheduler calls this task, which
# moves all keys of the form "flux:time-rollup:current:X" into rollups of the
# form "flux:time-rollup:1:X:{current time - 60 seconds}:{current time}". The
# number 1 in the previous key is the number of minute samples in the bucket;
# we'll call this the "accuracy" of the bucket. At most two rollups are kept
# per accuracy per bucket id and accuracies are only kept in powers of two.
#
# After the flux:time-rollup:current keys have all been rolled up into keys
# of accuracy 1, the rollup process tries to roll any counters of accuracy
# 1 into counters of accuracy 2, and so on, until there are no more counters
# to roll up. Since counters of accuracy 1 and greater have a start time and
# end time incorporated into their key, the start and end time of a rolled up
# key can be easily determined by taking the min of the start times and the
# max of the end times.
#
# The implementation of this task assumes that it's only called at most once
# per second. Otherwise, data can be lost during roll-ups. In practice, this
# task is called once a minute by resque-scheduler.

class TimeRangeRollup
  @queue = :rollup
  @log = Logger.new(STDOUT)
  @log.level = Logger::INFO

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
                          .select{ |bucket, group| group.length > 2 }

      break if keys_to_roll.empty?

      keys_to_roll.each do |bucket, keys|
        to_roll = keys.sort.take(2)
        min_rollup_time = to_roll.map{ |k| k.split(':')[-2].to_i }.sort.first
        max_rollup_time = to_roll.map{ |k| k.split(':')[-1].to_i }.sort.last
        new_key = "flux:time-rollup:#{current_stage * 2}:#{bucket}:#{min_rollup_time}:#{max_rollup_time}"
        @log.info { "Rolling #{to_roll.first} and #{to_roll.last} into #{new_key}" }
        counter.union_store(new_key, *to_roll)
        redis.del(*to_roll)
      end

      current_stage *= 2
    end

    @log.info { "Done with roll-up" }
  end
end
