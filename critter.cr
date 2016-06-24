# Copyright (C) 2016 Oleh Prypin <oleh@pryp.in>
# This file is part of Critter.
# Released under the terms of the MIT license (see LICENSE).

require "./options"
require "./irc"
require "./gitter"


class ChatOptions < Options
  string irc_host
  int    irc_port = 6667
  bool   irc_ssl = false
  string irc_channel
  string irc_nick
  string irc_password = nil
  string irc_username = "bridge"
  string irc_hostname = System.hostname
  string irc_realname = "bridge bot"
  string irc_quit_reason = "Shutting down"
  int    irc_read_timeout = 180
  int    irc_write_timeout = 5

  string gitter_api_key
  string gitter_room
  bool   gitter_prevent_emojis = false
  bool   gitter_insert_mentions = true   # "person: yes" -> "@person: yes"

  string contact_info = nil   # Textual information that the bot replies to private messages with
end


record Message, sender : String, text : String, priv = false, action = false, permalink : String? = nil



def start(options)
  chats = [IRC.new(options), Gitter.new(options)]

  chats.each do |chat|
    spawn do
      chat.run do |msg|
        chats.each do |to|
          next if to == chat
          to.send(msg) unless msg.priv
        end

        if msg.priv || (
          msg.text =~ /(@|, *|\b)#{Regex.escape(chat.nick)}(,|:|\b)/ &&
          !($~[1].empty? && $~[2].empty?)
        )
          text = "I'm a bot, *bleep, bloop*. I relay messages between"
          if msg.priv
            text += " IRC and Gitter rooms."
            text += " #{options.contact_info!}." if options.contact_info
            text += " Source code: https://github.com/blaxpirit/critter"
          else
            items = chats.map { |c| c == chat ? "here" : c.location }
            text += " #{items.join(" and ")}"
          end
          chat.tell Message.new(msg.sender, text, msg.priv)
        end
      end
    end
  end
end


argv = [] of String
rest = ARGV + [";"]
until rest.empty?
  index = rest.index(";").not_nil!
  argv += rest[0...index]
  start(ChatOptions.new(argv))
  rest = rest[index+1 .. -1]
end

loop do
  sleep 60
end
