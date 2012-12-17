require 'json'
require 'rack/test'

require './app.rb'


describe 'Flux' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  describe "following" do
    it "updates followers on the followed user" do
      get "/query?keys[]=user1:followers&maxResults=10"
      JSON.parse(last_response.body).should == { 'results' => [] }
      post "/events", [['client:gravity:action:follow:user', {follower: 'user2', followee: 'user1'}]].to_json
      get "/query?keys[]=user1:followers&maxResults=10"
      JSON.parse(last_response.body)['results'].should == ['user2']
    end
    it "updates sources on the following user" do
      get "/query?keys[]=user1:followers&maxResults=10"
      JSON.parse(last_response.body).should == { 'results' => [] }
      post "/events", [['client:gravity:action:follow:user', {follower: 'user2', followee: 'user1'}]].to_json
      get "/query?keys[]=user2:sources&maxResults=10"
      JSON.parse(last_response.body)['results'].should == ['user1']
    end
    it "doesn't add duplicates to the followed list even if the event fires multiple times" do
      get "/query?keys[]=user1:followers&maxResults=10"
      JSON.parse(last_response.body)['results'].should == []
      10.times do
        post "/events", [['client:gravity:action:follow:user', {follower: 'user2', followee: 'user1'}]].to_json
        post "/events", [['client:gravity:action:follow:user', {follower: 'user3', followee: 'user1'}]].to_json
      end
      get "/query?keys[]=user1:followers&maxResults=10"
      JSON.parse(last_response.body)['results'].sort.should == ['user2', 'user3']
    end
  end

  describe "unfollowing" do
    before(:each) do
      post "/events", [['client:gravity:action:follow:user', {follower: 'user2', followee: 'user1'}]].to_json
      post "/events", [['client:gravity:action:follow:user', {follower: 'user3', followee: 'user1'}]].to_json
      get "/query?keys[]=user1:followers&maxResults=10"
      JSON.parse(last_response.body)['results'].sort.should == ['user2', 'user3']
    end
    it "updates followers on the unfollowed user" do
      post "/events", [['client:gravity:action:unfollow:user', {follower: 'user3', followee: 'user1'}]].to_json
      get "/query?keys[]=user1:followers&maxResults=10"
      JSON.parse(last_response.body)['results'].sort.should == ['user2']
    end
    it "updates sources on the following user" do
      post "/events", [['client:gravity:action:unfollow:user', {follower: 'user3', followee: 'user1'}]].to_json
      get "/query?keys[]=user3:sources&maxResults=10"
      JSON.parse(last_response.body)['results'].sort.should == []
    end
    it "is a no-op if the user isn't following the user they're trying to unfollow in the first place" do
      post "/events", [['client:gravity:action:unfollow:user', {follower: 'user4', followee: 'user1'}]].to_json
      get "/query?keys[]=user1:followers&maxResults=10"
      JSON.parse(last_response.body)['results'].sort.should == ['user2', 'user3']
    end
  end

  describe "posting" do
    before(:each) do
      # 4 users, each user follows every user less than him/her.
      post "/events", [['client:gravity:action:follow:user', {follower: 'user2', followee: 'user1'}],
                       ['client:gravity:action:follow:user', {follower: 'user3', followee: 'user1'}],
                       ['client:gravity:action:follow:user', {follower: 'user3', followee: 'user2'}],
                       ['client:gravity:action:follow:user', {follower: 'user4', followee: 'user1'}],
                       ['client:gravity:action:follow:user', {follower: 'user4', followee: 'user2'}],
                       ['client:gravity:action:follow:user', {follower: 'user4', followee: 'user3'}]].to_json
    end
    it "updates the feed of all users following the poster" do
      post "/events", [['client:gravity:action:post', {user: 'user1', post: 'post1', '@targets' => ['[user].followers.feedItems'], '@add' => 'post'}]].to_json
      ['user2', 'user3', 'user4'].each do |user|
        get "/query?keys[]=#{user}:feedItems&maxResults=10"
        JSON.parse(last_response.body)['results'].should == ['post1']
      end
    end
    it "sends a sequence of posts to the correct subscribers" do
      4.times do |i| 
        post "/events", [['client:gravity:action:post', {user: "user#{i+1}", post: "post#{i+1}", '@targets' => ['[user].followers.feedItems'], '@add' => 'post'}]].to_json
      end
      get "/query?keys[]=user1:feedItems&maxResults=10"
      JSON.parse(last_response.body)['results'].sort.should == []
      get "/query?keys[]=user2:feedItems&maxResults=10"
      JSON.parse(last_response.body)['results'].sort.should == ['post1']
      get "/query?keys[]=user3:feedItems&maxResults=10"
      JSON.parse(last_response.body)['results'].sort.should == ['post1', 'post2']
      get "/query?keys[]=user4:feedItems&maxResults=10"
      JSON.parse(last_response.body)['results'].sort.should == ['post1', 'post2', 'post3']
    end
    it "returns most recently posted posts first" do
      post "/events", [['client:gravity:action:post', {user: "user1", post: "post1", '@targets' => ['[user].followers.feedItems'], '@add' => 'post'}],
                       ['client:gravity:action:post', {user: "user2", post: "post2", '@targets' => ['[user].followers.feedItems'], '@add' => 'post'}],
                       ['client:gravity:action:post', {user: "user3", post: "post3", '@targets' => ['[user].followers.feedItems'], '@add' => 'post'}],
                       ['client:gravity:action:post', {user: "user1", post: "post4", '@targets' => ['[user].followers.feedItems'], '@add' => 'post'}]].to_json
      get "/query?keys[]=user4:feedItems&maxResults=10"
      JSON.parse(last_response.body)['results'].should == ['post4', 'post3', 'post2', 'post1']
    end
    it "allows you to override the relative order of posts by manually specifying a time" do
      post "/events", [['client:gravity:action:post', {user: "user1", post: "post1", '@targets' => ['[user].followers.feedItems'], '@add' => 'post'}],
                       ['client:gravity:action:post', {user: "user2", post: "post2", '@targets' => ['[user].followers.feedItems'], '@add' => 'post'}],
                       ['client:gravity:action:post', {user: "user3", post: "post3", '@targets' => ['[user].followers.feedItems'], '@add' => 'post'}],
                       ['client:gravity:action:post', {user: "user1", post: "post4", '@score' => 1, '@targets' => ['[user].followers.feedItems'], '@add' => 'post'}]].to_json
      get "/query?keys[]=user4:feedItems&maxResults=10"
      JSON.parse(last_response.body)['results'].should == ['post3', 'post2', 'post1', 'post4']
    end
  end
end
