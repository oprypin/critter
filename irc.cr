# Copyright (C) 2016 Oleh Prypin <oleh@pryp.in>
# This file is part of Critter.
# Released under the terms of the MIT license (see LICENSE).

require "socket"
require "openssl"


class IRCConnection
  @socket : TCPSocket | OpenSSL::SSL::Socket::Client | Nil
  @orig_socket : TCPSocket | Nil
  @channels_regex : Regex?

  def initialize(@options : ChatOptions)
    @channels = {} of String => Channel(Message)
  end

  macro method_missing(call)
    @options.irc_{{call}}
  end

  private def connect
    socket = TCPSocket.new(host, port)
    socket.read_timeout = read_timeout
    socket.write_timeout = write_timeout
    socket.keepalive = true
    @socket = @orig_socket = socket
    if ssl
      @socket = socket = OpenSSL::SSL::Socket::Client.new(socket)
    end

    sleep 2.seconds
    write "NICK #{nick}"
    write "USER #{username} #{hostname} unused :#{realname}"
    if password
      write "PASS #{password}"
      #write "PRIVMSG NickServ :identify #{password}"
    end
    sleep 2.seconds
    @channels.each_key do |channel|
      write "JOIN #{channel}"
    end
  end

  def finalize
    write "QUIT :#{quit_reason}"
    @socket.try &.close
  rescue
  end

  def write(line)
    if password
      p line.gsub(password!, "[...]")
    else
      p line
    end
    @socket.not_nil! << line << "\r\n"
    @socket.not_nil!.flush
  end

  def subscribe(channel) : Channel
    @channels[channel.downcase] = result = Channel(Message).new
    recipients = (@channels.keys + [nick]).map { |k| Regex.escape(k) } .join("|")
    @channels_regex = /^:([^ ]+)![^ ]+ +PRIVMSG +(#{recipients}) :(.+)/i
    write "JOIN #{channel}" rescue nil
    result
  end

  def run
    wait_time = 2.0
    timeout = false
    loop do
      begin
        connect
        loop do
          begin
            line = @socket.not_nil!.gets
            raise "Disconnected" if !line || line.empty?
            timeout = false
            line = line.not_nil!.strip

            case line
            when /^PING\b(.*)/i
              write "PONG#{$~[1]}"
            when @channels_regex
              _, sender, recipient, msg = $~
              next if sender.downcase == nick.downcase

              if action = !!(msg =~ /^\001ACTION (.*)\001$/i)
                msg = $~[1]
              end

              msg = msg.gsub /\x03[0-9][0-9](?:,[0-9][0-9])?|[\x00-\x1f]/, ""

              puts "IRC: #{recipient} <#{sender}> #{msg.inspect}"
              if priv = (recipient.downcase == nick.downcase)
                recipient = @channels.keys[0]
              end
              @channels[recipient.downcase].send Message.new(
                sender, msg, priv: priv, action: action
              )
            when /^[^ ]+ +JOIN\b.*/i
              p line
            end

            wait_time = {wait_time / 2, 2.0}.max
          rescue e : InvalidByteSequenceError
            puts "#{e.class}: #{e.message}"
          rescue e : IO::Timeout
            puts "#{e.class}: #{e.message}"
            write "PING :#{hostname}"
            raise e if timeout
            timeout = true
          end
        end
      rescue e
        puts "#{e.class}: #{e.message}"
        @socket.try &.close rescue nil
        sleep wait_time
        wait_time *= 2
      end
    end
  end
end

class IRC
  @@connections = {} of {String, String} => IRCConnection
  @connection : IRCConnection
  @pipe : Channel(Message)

  def initialize(@options : ChatOptions)
    @connection = @@connections.fetch({host, nick}) {
      @@connections[{host, nick}] = conn = IRCConnection.new(@options)
      spawn { conn.run }
      conn
    }
    @pipe = @connection.subscribe channel
  end

  macro method_missing(call)
    @options.irc_{{call}}
  end

  def write(line)
    @connection.write line
  end

  def location
    "IRC (#{channel} on #{host})"
  end

  def run
    loop do
      yield @pipe.receive
    end
  end

  def send(msg : String, action = false, priv = false)
    ending = ""
    if action
      msg = "\001ACTION #{msg}"
      ending = "\001"
    end
    msg = "PRIVMSG #{channel} :#{msg}"
    cutoff = 450
    if msg.bytesize <= cutoff
      write msg + ending
      return
    end
    until (msg.byte_at cutoff - 1).chr.whitespace? || cutoff <= 410
      cutoff -= 1
    end
    write msg.byte_slice(0, cutoff) + ending
    send "\u{02}...\u{0f} " + msg.byte_slice(cutoff), action, priv
  end

  def send(msg : Message)
    lines = msg.text.split('\n')
    nlines = lines.size

    i = 0
    code_start = nil
    while i < lines.size
      line = lines[i].strip
      if !code_start
        if line.starts_with?("```") && !line.includes?(' ')
          code_start = i
        end
      else
        if line == "```"
          sub = lines[code_start+1..i-1].join(" ⏎ ")
          if i - code_start - 1 > 5 || sub.size > 90
            sub = "\u{1d}code paste, see link\u{0f}"
          end
          lines[code_start..i] = "```#{sub}```"
          i = code_start
        end
      end
      i += 1
    end

    sender = msg.action ? "* #{msg.sender}" : "<#{msg.sender}>"
    finish = ""
    if lines.size > 5
      lines.delete_at(5..-1)
      finish = " \u{02}...\u{0f}"
    end
    text = "\u{02}#{sender}\u{0f} " + lines.join(" ⏎ ")
    if text.size > 750
      text = text[0...750]
      finish = " \u{02}...\u{0f}"
    end
    text += finish
    if text.size > 750 || nlines > 3
      text += " [#{msg.permalink}]" if msg.permalink
    end

    send text, action: msg.action, priv: msg.priv
  end

  def tell(msg : Message)
    if msg.priv
      write "PRIVMSG #{msg.sender} :#{msg.text}"
    else
      send "#{msg.sender}, #{msg.text}"
    end
  end
end
