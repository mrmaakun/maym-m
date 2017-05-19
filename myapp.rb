# app.rb
require 'sinatra'
require 'line/bot'
require 'open-uri'
require 'httparty'

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

get '/' do
	logger.info "logger works"

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
        message = {
          type: 'text',
          text: '写真を送ってみてください！お客さんが既に送った写真を見たかったら、イベントのフェイスブックページを見てください: https://www.facebook.com/Mari-and-Marks-Wedding-646906422185940/'
        }
        client.reply_message(event['replyToken'], message)
      when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
        logger.info "Awesome: "
        logger.info event.message
        logger.info event.message['originalContentUrl']
        response = client.get_message_content(event.message['id'])
        tf = Tempfile.open("content")
        logger.info tf.path
        tf.write(response.body)
        filename = "public/images/image_#{event.message['id']}.jpg"
        logger.info filename
        out_file = File.open(filename, "a+")
        out_file << response.body
        out_file.close

        headers = { 
          "Authorization"  => "OAuth #{ENV["FB_PAGE_ACCESS_TOKEN"]}" 
        }

        response = HTTParty.post("https://graph.facebook.com/646906422185940/photos?url=http://maymm-photoshare.herokuapp.com/images/image_#{event.message['id']}.jpg", 
          :headers => headers
        }

  "OK"
end
