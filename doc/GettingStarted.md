Getting Started with Flux
=========================

Install SSH
-----------

Get a working SSH client. Generate a public/private key pair and upload it to
Github under [Account Settings, SSH Public Keys](https://github.com/account).
Refer to [troubleshooting ssh issues](http://help.github.com/troubleshooting-ssh/)
if you're having problems.

Install Git
-----------

Install [Git](http://git-scm.com/download).

Fork Flux
------------

Fork [Flux](https://github.com/artsy/flux "Flux"). Then, pull the source and get started.

    $ git clone git@github.com:<your-github-username>/flux.git

Install Ruby
------------

For Linux and OSX it's recommended that you install [RVM](http://rvm.beginrescueend.com/).

    $ bash < <(curl -s https://rvm.beginrescueend.com/install/rvm)

Add RVM path and initialization command to your .bash_profile

    export PATH=$PATH:/usr/local/rvm/bin
    [[ -s "$HOME/.rvm/scripts/rvm" ]] && . "$HOME/.rvm/scripts/rvm"

Open a new shell and test RVM. The following should return `rvm is a function`.

    $ type rvm | head -1
    rvm is a function

Install Ruby 1.9.2, RubyGems and Rails.

    $ rvm install 1.9.2
    $ rvm --default 1.9.2

Test Ruby
---------

    $ ruby -ropenssl -rzlib -rreadline -e "puts :Hello"

Install Bundler and Gems
------------------------

    $ gem install bundler

Change your current directory to the checked out source and run bundler.

    $ bundle install

Installing Redis
----------------

On OSX, install Redis using Homebrew:

    $ brew install redis

...and if redis-server isn't already running:

    $ redis-server /usr/local/etc/redis.conf

On Linux, install Redis using `apt-get`:

    $ sudo apt-get install redis-server

Running Flux
------------

Flux runs under [Foreman](http://ddollar.github.com/foreman/), which
launches and monitors 3 processes: the Flux Sinatra app, a Resque
worker, and the Resque Sinatra app. Launch all three in a development
environment with

    $ bundle exec foreman start

The Flux Sinatra app runs on localhost:5000 and the Resque admin app
runs on localhost:5100.

You can try out generating events and running queries via curl:

    $ curl --data "[[\"client:gravity:action:follow:user\",{\"follower\":\"user:2\", \"followee\":\"user:1\"}]]" http://localhost:5000/events
    $ curl --data "[[\"client:gravity:action:post\",{\"user\":\"user:1\", \"post\":\"post:1\", \"@targets\":[\"[user].followers.feedItems\"], \"@add\":\"post\"}]]" http://localhost:5000/events
    $ curl "http://localhost:5000/query?keys\[\]=user:2:feedItems" && echo
    {"results":["post:1"]}
    $