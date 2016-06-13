# Copyright (C) 2016 Oleh Prypin <oleh@pryp.in>
# This file is part of Critter.
# Released under the terms of the MIT license (see LICENSE).

require "http"
require "json"


class Gitter
  @room_id : String
  @user_id : String
  @user_name : String

  def initialize(@options : ChatOptions)
    @headers = HTTP::Headers{
      "Authorization" => "Bearer #{api_key}",
      "Accept" => "application/json",
      "Content-Type" => "application/json",
    }

    js = JSON.parse(
      request :POST, "rooms", uri: room
    )
    @room_id = js["id"].as_s

    js = JSON.parse(request :GET, "user")
    @user_id = js[0]["id"].as_s
    @user_name = js[0]["username"].as_s
  end

  macro method_missing(call)
    @options.gitter_{{call}}
  end

  def url
    "https://gitter.im/#{room}"
  end

  def nick
    @user_name
  end

  private def request(_method, _path, **arguments)
    url = "https://api.gitter.im/v1/#{_path}"
    puts "#{_method} #{url} #{arguments.to_json}"
    HTTP::Client.exec(
      _method.to_s, url, headers: @headers.dup, body: arguments.to_json
    ).body
  end

  def send(msg : String)
    request :POST, "rooms/#{@room_id}/chatMessages", text: msg
  end

  def send(msg : Message)
    action = "\\*" if msg.action
    send "**<#{msg.sender}>** #{action}#{msg.text}"
  end

  def tell(msg : Message)
    send "@#{msg.sender}, #{msg.text}"
  end

  def run
    wait_time = 1.0
    stream_url = "https://stream.gitter.im/v1/rooms/#{@room_id}/chatMessages"
    loop do
      begin
        puts "GET #{stream_url}"
        HTTP::Client.get(stream_url, headers: @headers.dup) do |resp|
          puts "Connected to Gitter #{room}"
          buf = ""
          resp.body_io.each_line "}" do |line|
            buf += line
            # "Streaming" JSON
            begin
              msg = JSON.parse(buf)
            rescue
              next
            end
            buf = ""

            sender = msg["fromUser"]["username"].as_s
            next if sender == @user_name

            id = msg["id"].as_s
            text = msg["text"].as_s.strip
            if action = !!msg["status"]?
              text = text.split(2)[-1]
            end

            puts "Gitter: #{room} <#{sender}> #{text.inspect}"
            yield Message.new(sender, text, action: action, permalink: "#{url}?at=#{id}")

            wait_time = {wait_time / 2, 1.0}.max

            # Mark as read
            request :POST, "user/#{@user_id}/rooms/#{room}/unreadItems", chat: [id]
          end
        end
      rescue e
        puts "#{e.class}: #{e.message}"
        sleep wait_time
        wait_time *= 2
      end
    end
  end
end
