# app.rb
require 'sinatra'
require 'line/bot'
require 'open-uri'
require 'httparty'
require 'googleauth'
require 'google/api_client/client_secrets'
require 'redis'
require 'json'
require 'date'
require 'nokogiri'


if ENV['GOOGLE_CREDENTIALS'] != "NONE"

  credential_file = File.open("credentials.json", "a+")
  credential_file << ENV['GOOGLE_CREDENTIALS']
  credential_file.close
end

redis = Redis.new(:url => ENV["REDIS_URL"], :port => 13449, :db => 0)

client_secrets = Google::APIClient::ClientSecrets.load("credentials.json")
auth_client = client_secrets.to_authorization
auth_client.update!(
  :scope => 'https://picasaweb.google.com/data/',
  :redirect_uri => "#{ENV["HOSTNAME"]}oauth2callback",
)

def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

class FacebookAPI
  include HTTParty
  base_uri 'api.stackexchange.com'

  def initialize(service, page)
    @options = { query: { site: service, page: page } }
  end

  def questions
    self.class.get("/2.2/questions", @options)
  end

  def users
    self.class.get("/2.2/users", @options)
  end
end

get '/checktokens' do
    logger.info "Access token: #{redis.get("access_token")}"
    logger.info "Refresh token: #{redis.get("refresh_token")}"
end

get '/refresh' do

  refresh_token!
  logger.info "Access token: #{redis.get("access_token")}"
  logger.info "Refresh token: #{redis.get("refresh_token")}"

end

get '/oauth2callback' do
  if request['code'] == nil
    auth_uri = auth_client.authorization_uri.to_s
    redirect to(auth_uri)
  else
    auth_client.code = request['code']
    auth_client.fetch_access_token!
    auth_client.client_secret = nil
    logger.info auth_client.to_json
    parsed_credentials = JSON.parse(auth_client.to_json)
    redis.set("access_token", parsed_credentials['access_token'])
    redis.set("refresh_token", parsed_credentials['refresh_token'])

    logger.info "Access token: #{redis.get("access_token")}"
    logger.info "Refresh token: #{redis.get("refresh_token")}"

    redirect to('/authcomplete')
  end
end

get '/authcomplete' do
  "Now the bot is authorized to publish to Google Photos!"
end


get '/googleauth' do
  auth_uri = auth_client.authorization_uri.to_s
  redirect auth_uri


end

post '/callback' do
  body = request.body.read

  signature = request.env['HTTP_X_LINE_SIGNATURE']
  unless client.validate_signature(body, signature)
    error 400 do 'Bad Request' end
  end

  events = client.parse_events_from(body)
  events.each { |event|
    case event
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text
        logger.info "text message"

        if event.message['text'].include? "次会"
          message = {
          type: 'text',
          text: "2次会はパセラリゾーツ グランデ 渋谷店でやります！ 受付は20:30から、スタートは21:00です！是非遊びに着てください！ https://goo.gl/aR74bV"
        }
        client.reply_message(event['replyToken'], message)
          return
        end

        if event.message['text'].downcase.include? "english"
          message = {
          type: "text",
          text: "eigo wakarimasen!!"
        }
        client.reply_message(event['replyToken'], message)
          return
        end

        if event.message['text'].downcase.include? "facebook" or event.message['text'].include? "フェィスブック"
          message = {
          type: "text",
          text: "結婚式の正式なFacebook Pageはこちらにあります! \n https://goo.gl/lKQKdS"
        }
        client.reply_message(event['replyToken'], message)
          return
        end

        message = {
          type: 'text',
          text: "写真を送ってみてください！お客様が既に送った写真を見たかったら、ウェディングアルバムを見てください! \n https://goo.gl/photos/jnZm9JKGdFKfgwvVA"
        }
        client.reply_message(event['replyToken'], message)
      when Line::Bot::Event::MessageType::Image
        logger.info event.message
        response = client.get_message_content(event.message['id'])

        # save file to disk temporarily
        filename = "public/images/image_#{event.message['id']}.jpg"
        logger.info filename
        image_data = response.body
        out_file = File.open(filename, "a+")
        out_file << response.body
        out_file.close

        message = {
          type: 'text',
          text: "写真送ってくれてありがとう! ウェディングアルバムにアップロードするね〜　アルバムはこのリンクから見られる! \n https://goo.gl/photos/jnZm9JKGdFKfgwvVA"
        }
        client.reply_message(event['replyToken'], message)

          

            # post file to facebook
          #  headers = { 
          #    "Authorization"  => "OAuth #{ENV["FB_PAGE_ACCESS_TOKEN"]}" 
          #  }

          #  response = HTTParty.post("https://graph.facebook.com/646906422185940/photos?url=http://maymm-photoshare.herokuapp.com/images/image_#{event.message['id']}.jpg", 
          #    :headers => headers
          #  )


            # post file to google photos

        headers = { 
          "Authorization"  => "Bearer #{redis.get("access_token")}",
          "Content-Type" => "image/jpeg"
        }
        response = HTTParty.post("https://picasaweb.google.com/data/feed/api/user/default/albumid/6421730192211333473", 
          :headers => headers,
          :body => image_data
        )

        logger.info response.parsed_response

        # Refresh if response fails
        if response.parsed_response.include? "Token expired"

          logger.info "Token error occurred so we will refresh the token."
          refresh_token!

          headers = { 
            "Authorization"  => "Bearer #{redis.get("access_token")}",
            "Content-Type" => "image/jpeg"
          }
          response = HTTParty.post("https://picasaweb.google.com/data/feed/api/user/default/albumid/6421730192211333473", 
            :headers => headers,
            :body => image_data
          )
          logger.info response_json

        end



        # delete file after we're done to save space
        File.delete(filename)

      when Line::Bot::Event::MessageType::Video

        logger.info event.message
        response = client.get_message_content(event.message['id'])

        # save file to disk temporarily
        filename = "public/images/video_#{event.message['id']}.mp4"
        logger.info filename
        image_data = response.body
        out_file = File.open(filename, "a+")
        out_file << response.body
        out_file.close

        message = {
          type: 'text',
          text: "写真送ってくれてありがとう! ウェディングアルバムにアップロードするね〜　アルバムはこのリンクから見られる! \n https://goo.gl/photos/jnZm9JKGdFKfgwvVA"
        }
        client.reply_message(event['replyToken'], message)

        BOUNDARY = "END_OF_PART"

        headers = { 
          "Authorization"  => "Bearer #{redis.get("access_token")}",
          "Content-Type" => "multipart/form-data, boundary=#{BOUNDARY}"
        }
        post_body = []

        builder = Nokogiri::XML::Builder.new { |xml|
          xml.entry('xmlns' => 'http://www.w3.org/2005/Atom') do
            xml.title "title"
            xml.summary "Summary"
            xml.object(:scheme => "http://schemas.google.com/g/2005#kind", :term => "http://schemas.google.com/photos/2007#photo")
          end
        }
        
        xml_text = builder.to_xml save_with:Nokogiri::XML::Node::SaveOptions::NO_DECLARATION
        
	       puts xml_text
	
	       # Add the XML
        post_body << "--#{BOUNDARY}\r\n"
        post_body << "Content-Type: application/atom+xml\r\n\r\n"
        post_body << xml_text
        post_body << "\r\n\r\n--#{BOUNDARY}--\r\n"

        # Add the file Data
        post_body << "--#{BOUNDARY}\r\n"
        post_body << "Content-Type: #{MIME::Types.type_for(file)}\r\n\r\n"
        post_body << image_data      

        response = HTTParty.post("https://picasaweb.google.com/data/feed/api/user/default/albumid/6421730192211333473", 
          :headers => headers,
          :body => post_body
        )

        logger.info response.parsed_response

        # Refresh if response fails
        if response.parsed_response.include? "Token expired"

          logger.info "Token error occurred so we will refresh the token."
          refresh_token!

          headers = { 
            "Authorization"  => "Bearer #{redis.get("access_token")}",
            "Content-Type" => "video/mp4"
          }
          response = HTTParty.post("https://picasaweb.google.com/data/feed/api/user/default/albumid/6421730192211333473", 
            :headers => headers,
            :body => image_data
          )
          logger.info response_json

        end

	     end

     end
   }

  "OK"
end

# Google token refresh code

def to_params
  { 'refresh_token' => redis.get("refresh_token"),
    'client_id'     => ENV['CLIENT_ID'],
    'client_secret' => ENV['CLIENT_SECRET'],
    'grant_type'    => 'refresh_token'
  }
end

def refresh_token!

    redis = Redis.new(:url => ENV["REDIS_URL"], :port => 13449, :db => 0)

    response = HTTParty.post("https://accounts.google.com/o/oauth2/token",
        body: {
            grant_type: "refresh_token",
            client_id: ENV['GOOGLE_CLIENT_ID'],
            client_secret: ENV['GOOGLE_CLIENT_SECRET'],
            refresh_token: redis.get("refresh_token")
            })
    response = JSON.parse(response.body)
    logger.info response
    redis.set("access_token", response["access_token"])
    redis.set("expires_at", response["expires_in"])
end


