# Copyright (C) 2016 Oleh Prypin <oleh@pryp.in>
# This file is part of Critter.
# Released under the terms of the MIT license (see LICENSE).

require "socket"
require "openssl"


alias Pipe = Channel::Unbuffered

class IRCConnection
  @socket : TCPSocket | OpenSSL::SSL::Socket::Client | Nil
  @channels_regex : Regex?

  def initialize(@options : ChatOptions)
    @channels = {} of String => Pipe(Message)
  end

  macro method_missing(call)
    @options.irc_{{call}}
  end

  private def connect
    socket = TCPSocket.new(host, port)
    socket.read_timeout = 300
    socket.write_timeout = 5
    socket.keepalive = true
    if ssl
      socket = OpenSSL::SSL::Socket::Client.new(socket)
    end
    @socket = socket
    at_exit { finalize }

    write "NICK #{nick}"
    write "USER #{username} #{hostname} unused :#{realname}"
    if password?
      write "PASS #{password}"
      #write "PRIVMSG NickServ :identify #{password}"
      sleep 2.seconds
    end
  end

  def finalize
    write "QUIT :#{quit_reason}"
    @socket.try &.close
  rescue
  end

  def write(line)
    line = line.gsub(password, "[...]") if password?
    @socket.not_nil! << line << "\r\n"
  end

  def subscribe(channel) : Pipe
    @channels[channel.downcase] = result = Pipe(Message).new
    recipients = (@channels.keys + [nick]).map { |k| Regex.escape(k) } .join("|")
    @channels_regex = /^:([^ ]+)![^ ]+ +PRIVMSG +(#{recipients}) :(.+)/i
    result
  end

  def run
    wait_time = 1.0
    loop do
      begin
        connect
        loop do
          begin
            line = @socket.not_nil!.gets
            raise "Disconnected" if !line || line.empty?
            line = line.not_nil!.strip

            puts line

            case line
            when /^PING\b(.*)/i
              write "PONG#{$~[1]}"
            when @channels_regex
              _, sender, recipient, msg = $~
              next if sender.downcase == nick.downcase
              puts "IRC: #{recipient} <#{sender}> #{msg.inspect}"
              if (priv = recipient.downcase == nick.downcase)
                recipient = @channels.keys[0]
              end
              @channels[recipient.downcase].send Message.new(sender, msg, priv: priv)
            when /^[^ ]+ +JOIN\b.*/i
              puts line
            end

            wait_time = {wait_time / 2, 1.0}.max
          rescue e : InvalidByteSequenceError
            puts "#{e.class}: #{e.message}"
          end
        end
      rescue e
        puts "#{e.class}: #{e.message}"
        finalize
        sleep wait_time
        wait_time *= 2
      end
    end
  end
end

class IRC
  @@connections = {} of {String, String} => IRCConnection
  @connection : IRCConnection
  @pipe : Pipe(Message)

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

  def url
    chan = channel
    chan = chan[1..-1] if chan =~ /^#[^#]/
    "irc://#{host}/#{chan}"
  end

  def run
    write "JOIN #{channel}"
    loop do
      yield @pipe.receive
    end
  end

  def send(msg : String, priv = false)
    msg = "PRIVMSG #{channel} :#{msg}"
    cutoff = 470
    if msg.bytesize <= cutoff
      write msg
      return
    end
    until (msg.byte_at cutoff - 1).chr.whitespace? || cutoff <= 420
      cutoff -= 1
    end
    write msg.byte_slice(0, cutoff)
    send "\u{02}...\u{0f} " + msg.byte_slice(cutoff)
  end

  def send(msg : Message)
    nlines = msg.text.lines.size
    text = "\u{02}<#{msg.sender}>\u{0f} " + msg.text.gsub('\n', " ⏎ ")
    if text.size > 750
      text = text[0...750] + " \u{02}...\u{0f}"
    end
    if text.size > 750 || nlines > 3
      text += " [#{msg.permalink}]" if msg.permalink
    end

    send text, priv: msg.priv
  end

  def tell(msg : Message)
    if msg.priv
      write "PRIVMSG #{msg.sender} :#{msg.text}"
    else
      send "#{msg.sender}, #{msg.text}"
    end
  end
end
