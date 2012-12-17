require 'json'
require 'rack/test'

require './app.rb'


describe 'Flux' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  describe "query paging" do
    before(:each) do
      100.times { |i| post "/events", [['client:gravity:action:follow:user', {followee: 'user0', follower: "user#{i+1}"}]].to_json }
    end
    it "returns a cursor as part of the result set if results aren't exhausted" do
      get "/query?keys[]=user0:followers&maxResults=10"
      JSON.parse(last_response.body)['next'].should_not be_nil
    end
    it "allows paging through results by passing the cursor back in" do
      accumulated_results = []
      result_set_size = 1

      get "/query?keys[]=user0:followers&maxResults=#{result_set_size}"
      result = JSON.parse(last_response.body)
      next_cursor = result['next']
      accumulated_results += result['results']

      while result['next'] do
        get "/query?keys[]=user0:followers&maxResults=#{result_set_size}&cursor=#{next_cursor}"
        result = JSON.parse(last_response.body)
        accumulated_results += result['results']
        next_cursor = result['next']
        result_set_size += 1
      end

      accumulated_results.should == 100.times.map{ |i| "user#{100-i}" }
    end
    it "properly returns and pages the union of multiple sets" do
      accumulated_results = []
      result_set_size = 1

      5.times do |i|
        post "/events", [['client:gravity:action:follow:user', {follower: "user#{3*i+1}", followee: 'user1', '@score' => 3*i+1}],
                         ['client:gravity:action:follow:user', {follower: "user#{3*i+2}", followee: 'user2', '@score' => 3*i+2}],
                         ['client:gravity:action:follow:user', {follower: "user#{3*i+3}", followee: 'user3', '@score' => 3*i+3}],
                         ['client:gravity:action:follow:user', {follower: "user#{3*i+3}", followee: 'user1', '@score' => 3*i+3}]].to_json
      end

      get "/query?keys[]=user1:followers&keys[]=user2:followers&keys[]=user3:followers&maxResults=#{result_set_size}"
      result = JSON.parse(last_response.body)
      next_cursor = result['next']
      accumulated_results += result['results']

      while result['next'] do
        get "/query?keys[]=user1:followers&keys[]=user2:followers&keys[]=user3:followers&maxResults=#{result_set_size}&cursor=#{next_cursor}"
        result = JSON.parse(last_response.body)
        accumulated_results += result['results']
        next_cursor = result['next']
        result_set_size += 1
      end

      accumulated_results.should == 15.times.map{ |i| "user#{15-i}" }
    end

    it "returns at most 50 results if you don't pass a maxResults parameter" do
      get "/query?keys[]=user0:followers"
      response_json = JSON.parse(last_response.body)
      response_json['next'].should_not be_nil
      response_json['results'].length.should == 50
    end
    it "returns at most 50 results if you ask for too many results" do
      get "/query?keys[]=user0:followers&maxResults=100"
      response_json = JSON.parse(last_response.body)
      response_json['next'].should_not be_nil
      response_json['results'].length.should == 50
    end
    
    describe "score ranges" do
      before(:each) do
        post "/events", [['client:gravity:action:follow:user', {follower: "user2", followee: 'user1', '@score' => 8}],
                         ['client:gravity:action:follow:user', {follower: "user3", followee: 'user1', '@score' => 9}],
                         ['client:gravity:action:follow:user', {follower: "user4", followee: 'user1', '@score' => 10}],
                         ['client:gravity:action:follow:user', {follower: "user5", followee: 'user1', '@score' => 11}],
                         ['client:gravity:action:follow:user', {follower: "user6", followee: 'user1', '@score' => 12}]].to_json
      end
      it "accepts a maxScore argument to restrict results" do
        get "/query?keys[]=user1:followers&maxScore=10"
        response_json = JSON.parse(last_response.body)
        response_json['results'].sort.should == ['user2', 'user3', 'user4'].sort
      end
      it "accepts a minScore argument to restrict results" do
        get "/query?keys[]=user1:followers&minScore=10"
        response_json = JSON.parse(last_response.body)
        response_json['results'].sort.should == ['user5', 'user6'].sort
      end
      it "accepts both a minScore and maxScore to define a range of scores" do
        get "/query?keys[]=user1:followers&minScore=9&maxScore=11"
        response_json = JSON.parse(last_response.body)
        response_json['results'].sort.should == ['user4', 'user5'].sort
      end
      it "doesn't get confused when an empty range is specified by minScore and maxScore" do
        get "/query?keys[]=user1:followers&minScore=11&maxScore=9"
        response_json = JSON.parse(last_response.body)
        response_json['results'].should be_empty        
      end
    end
  end

  describe "distinct counts" do
    it "returns a decent correct distinct add event count for a set" do
      10.times { 50.times { |i| post "/events", [['client:gravity:action:follow:user', {follower: "user#{i+1}", followee: 'user0'}]].to_json } }
      get "/distinct?keys[]=user0:followers"
      JSON.parse(last_response.body)['count'].should be_within(10).of(50)
    end
    it "returns 0 if the set doesn't exist" do
      get "/distinct?keys[]=badUser:followers"
      JSON.parse(last_response.body)['count'].should == 0
    end
    it "returns a correct union count for sets" do
      10.times { 50.times { |i| post "/events", [['client:gravity:action:follow:user', {follower: "user#{i+1}", followee: 'user0'}]].to_json } }
      10.times { 50.times { |i| post "/events", [['client:gravity:action:follow:user', {follower: "user#{i+31}", followee: 'user1'}]].to_json } } 
      get "/distinct?keys[]=user0:followers&keys[]=user1:followers&op=union"
      JSON.parse(last_response.body)['count'].should be_within(10).of(80)
    end
    it "returns a correct intersection count for sets" do
      10.times { 50.times { |i| post "/events", [['client:gravity:action:follow:user', {follower: "user#{i+1}", followee: 'user0'}]].to_json } }
      10.times { 50.times { |i| post "/events", [['client:gravity:action:follow:user', {follower: "user#{i+21}", followee: 'user1'}]].to_json } } 
      get "/distinct?keys[]=user0:followers&keys[]=user1:followers&op=intersection"
      JSON.parse(last_response.body)['count'].should be_within(10).of(30)
    end
    it "accepts a minScore argument to restrict results" do
      10.times { 50.times { |i| post "/events", [['client:gravity:action:follow:user', {follower: "user#{i+1}", followee: 'user0', '@score' => i+1}]].to_json } } 
      get "/distinct?keys[]=user0:followers&minScore=40"
      JSON.parse(last_response.body)['count'].should be_within(5).of(10)
    end
    it "raises an error if maxScore is passed" do
      get "/distinct?keys[]=user0:followers&maxScore=9000"
      last_response.status.should == 400
    end
  end

  describe "gross counts" do
    it "returns a correct gross add event count for a set" do
      17.times { |i| post "/events", [['client:gravity:action:follow:user', {follower: "user#{i+1}", followee: 'user0'}]].to_json }
      17.times { |i| post "/events", [['client:gravity:action:unfollow:user', {follower: "user#{i+1}", followee: 'user0'}]].to_json }
      get "/gross?keys[]=user0:followers"
      JSON.parse(last_response.body)['count'].should be_within(5).of(17)
    end
    it "returns 0 if the set doesn't exist" do
      get "/gross?keys[]=badUser:followers"
      JSON.parse(last_response.body)['count'].should == 0
    end
    it "returns a correct concatenated count for sets" do
      17.times { |i| post "/events", [['client:gravity:action:follow:user', {follower: "user#{i+1}", followee: 'user0'}]].to_json }
      17.times { |i| post "/events", [['client:gravity:action:unfollow:user', {follower: "user#{i+1}", followee: 'user0'}]].to_json }
      17.times { |i| post "/events", [['client:gravity:action:follow:user', {follower: "user#{i+1}", followee: 'user1'}]].to_json }
      17.times { |i| post "/events", [['client:gravity:action:unfollow:user', {follower: "user#{i+1}", followee: 'user1'}]].to_json }
      get "/gross?keys[]=user0:followers&keys[]=user1:followers"
      JSON.parse(last_response.body)['count'].should be_within(10).of(34)
    end
    it "counts keys added with the same op counter to be identical" do
      5.times do
        17.times { |i| post "/events", [['client:gravity:action:follow:user', {follower: "user#{i+1}", followee: 'user0', '@score' => 1}]].to_json }
        17.times { |i| post "/events", [['client:gravity:action:unfollow:user', {follower: "user#{i+1}", followee: 'user0', '@score' => 1}]].to_json }
      end
      17.times { |i| post "/events", [['client:gravity:action:follow:user', {follower: "user#{i+1}", followee: 'user0'}]].to_json }
      17.times { |i| post "/events", [['client:gravity:action:unfollow:user', {follower: "user#{i+1}", followee: 'user0'}]].to_json }
      get "/gross?keys[]=user0:followers&keys[]=user1:followers"
      JSON.parse(last_response.body)['count'].should be_within(10).of(34)
    end
    it "accepts a minScore argument to restrict results" do
      50.times { |i| post "/events", [['client:gravity:action:follow:user', {follower: "user#{i+1}", followee: 'user0', '@score' => i+1}]].to_json }
      get "/distinct?keys[]=user0:followers&minScore=40"
      JSON.parse(last_response.body)['count'].should be_within(5).of(10)      
    end
    it "raises an error if maxScore is passed" do
      get "/gross?keys[]=user0:followers&maxScore=9000"
      last_response.status.should == 400
    end
  end

  describe "up" do
    it "returns 'redis': true if Redis is up" do
      get "/up"
      JSON.parse(last_response.body)['redis'].should == true
    end
    it "returns 'redis': false if Redis is down" do
      MQLTranslator.any_instance.stub(:redis_up?) { false }
      get "/up"
      JSON.parse(last_response.body)['redis'].should == false
    end
  end

  describe "read-only mode" do
    before do
      ENV['READ_ONLY'] = "1"
    end
    after do
      ENV['READ_ONLY'] = nil
    end
    it "rejects events if the READ_ONLY environment variable is set" do
      get "/query?keys[]=user1:followers&maxResults=10"
      last_response.status.should == 200
      post "/events", [['client:gravity:action:follow:user', {follower: "user2", followee: 'user1'}]].to_json
      last_response.status.should == 501
    end
  end

end
