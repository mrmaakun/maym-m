
require 'httparty'
require 'redis'
require 'json'
require 'date'

desc "Refresh Google Access Token"
task :refresh_google do
      redis = Redis.new(:url => ENV["REDIS_URL"], :port => 13449, :db => 0)

    response = HTTParty.post("https://accounts.google.com/o/oauth2/token",
        body: {
            grant_type: "refresh_token",
            client_id: ENV['GOOGLE_CLIENT_ID'],
            client_secret: ENV['GOOGLE_CLIENT_SECRET'],
            refresh_token: redis.get("refresh_token")
            })
    response = JSON.parse(response.body)
    puts response

    if !response.has_key? "error"
        redis.set("access_token", response["access_token"])
    else
        puts "ERROR: #{response["error_description"]}"
    end
end
