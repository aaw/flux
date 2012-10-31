require 'spec_helper'
require 'timecop'

require './time_range_rollup.rb'

MINUTE=60
HOUR=MINUTE*60
DAY=HOUR*24
WEEK=DAY*7

describe TimeRangeRollup do
  it "does something with timecop" do
    puts "The time is #{Time.now}"
    Timecop.travel(Time.now - WEEK) do
      puts "The time is #{Time.now}"
    end
  end
end

