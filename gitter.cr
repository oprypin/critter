# Copyright (C) 2016 Oleh Prypin <oleh@pryp.in>
# This file is part of Critter.
# Released under the terms of the MIT license (see LICENSE).

require "http"
require "json"
require "markdown"


class Gitter
  @room_id : String
  @user_id : String
  @user_name : String
  @participants = Set(String).new

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

  def location
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

  def send(msg : String, action = false)
    request :POST, "rooms/#{@room_id}/chatMessages", text: msg, status: action
  end

  private def escape_emojis(s : String)
    s.gsub(
      /:-?[)\[@(*\/S|$O]|[:;]-?[\]DP]|X-D|:['’]-?\(|;-?\)|:-X|<\/?3|:[+\-]1:/i
    ) {
      if $~.begin == 0 || s[$~.begin.not_nil! - 1].whitespace? || $~.end == s.size
        $~[0].insert($~[0].size/2, '\u{2060}')
      else; $~[0]; end
    }
  end

  def send(msg : Message)
    sender = msg.action ? "\\* #{msg.sender}" : "<#{msg.sender}>"
    text = msg.text

    if insert_mentions
      text = text.sub /^([^ ]+)[,:] / {
        "#{"@" if @participants.includes? $~[1]}#{$~[0]}"
      }
    end

    if prevent_emojis
      # Add zero-width joiner to disrupt emoticon replacement
      text = String.build do |io|
        prev = 0
        # But not inside code blocks
        text.scan(/(?<!\\)`([^`]|\\`)+`/) do |m|
          io << escape_emojis(text[prev ... m.begin.not_nil!])
          io << m[0]
          prev = m.end.not_nil!
        end
        io << escape_emojis(text[prev..-1])
      end
    end

    send "**#{sender}** #{text}"
  end

  def tell(msg : Message)
    send "@#{msg.sender}, #{msg.text}"
  end

  def run
    wait_time = 1.0
    loop do
      begin
        puts "GET https://stream.gitter.im/v1/rooms/#{@room_id}/chatMessages"
        client = HTTP::Client.new("stream.gitter.im", tls: true)
        client.connect_timeout = 10.seconds
        client.read_timeout = 3.minutes
        client.get("/v1/rooms/#{@room_id}/chatMessages", headers: @headers.dup) do |resp|
          puts "Connected to Gitter #{room}"
          resp.body_io.each_line do |line|
            line = line.strip
            next if line.empty?
            msg = JSON.parse(line)

            sender = msg["fromUser"]["username"].as_s
            next if sender == @user_name
            @participants << sender

            id = msg["id"].as_s
            text = msg["text"].as_s.strip
            if action = !!msg["status"]?
              text = text.split(2)[-1]  # Drop @nickname
            end

            puts "Gitter: #{room} <#{sender}> #{text.inspect}"

            text = String.build do |io|
              renderer = MarkdownTextRenderer.new(io)
              Markdown::Parser.new(text, renderer).parse
            end

            yield Message.new(sender, text, action: action, permalink: "#{location}?at=#{id}")

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


private class MarkdownTextRenderer
  include Markdown::Renderer

  @url : String?
  @list_index = 0

  def initialize(@io : IO)
  end

  def begin_paragraph
  end
  def end_paragraph
  end

  def begin_italic
    @io << "*"
  end
  def end_italic
    @io << "*"
  end
  def begin_bold
    @io << "*"
  end
  def end_bold
    @io << "*"
  end

  def begin_header(level)
    @io << (level == 1 ? "===" : "---")
  end
  def end_header(level)
    @io << (level == 1 ? "===" : "---")
  end

  def begin_inline_code
    @io << "`"
  end
  def end_inline_code
    @io << "`"
  end

  def begin_code(language)
    @io << "```\n"
  end
  def end_code
    @io << "\n```"
  end

  def begin_quote
    @io << "> "
  end
  def end_quote
  end

  def begin_unordered_list
    @list_index = 0
  end
  def end_unordered_list
  end

  def begin_ordered_list
    @list_index = 0
  end
  def end_ordered_list
  end

  def begin_list_item
    @io << "\n" if @list_index > 0
    @io << (@list_index += 1) << ") "
  end
  def end_list_item
  end

  def begin_link(@url)
  end
  def end_link
    @io << " (" << @url << ")"
    @url = nil
  end

  def image(url, alt)
    @io << "(" unless @url
    unless @url && url =~ %r(/thumb/[^/]+$)
      @io << "(" << url << ")"
    end
    @io << ")" unless @url
  end

  def text(text)
    @io << text
  end

  def horizontal_rule
    @io << "\n"
  end
end
