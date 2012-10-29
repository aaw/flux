web: bundle exec ruby app.rb -o localhost -p $PORT
resqueweb: bundle exec resque-web --no-launch --foreground -o localhost -p $PORT -r ${RESQUE_REDIS_URL:-redis://localhost:6379/1}
resqueworker: bundle exec rake resque:work
resquescheduler: bundle exec rake resque:scheduler
