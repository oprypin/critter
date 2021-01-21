# ![Critter](logo.png "CRITTER")

### Chat bot relaying messages between [IRC][] and [Gitter][]

Requires [Crystal][] 0.34 or later to compile.

Check it out: [on Gitter](https://gitter.im/blaxpirit/critter) / [*#critterbot* on freenode](https://webchat.freenode.net/?channels=%23critterbot&prompt=1&randomnick=1)

The messages are sent from one nickname &ndash; a special bot account, both on IRC and Gitter. It looks like this:

- Gitter:

  > **Oleh Prypin** @BlaXpirit  23:25  
  > Writing from Gitter
  >
  > **Bridge bot** @bot         23:27  
  > **\<BlaXpirit>** Writing from IRC

- IRC:

  > [23:25] **\<bot>** **\<BlaXpirit>** Writing from Gitter
  >
  > [23:27] **\<BlaXpirit>** Writing from IRC

The bot replies to mentions and private messages, giving information about itself. It does not respond to `!commands` of any sort.

Long/multiline messages (primarily code pastes) from Gitter are collapsed when sending to IRC, but a link to the original message is provided.

#### Usage example:

```bash
critter \
--irc-host=chat.freenode.net --irc-port=6697 --irc-ssl=yes --irc-nick=FromGitter    \
--irc-password='Pa$$word' --gitter-api-key=da39a3ee5e6b4b0d3255bfef95601890afd80709 \
--contact-info="Contact ... on freenode or email bridge@example.org for support"    \
--irc-channel=##my-channel --gitter-room=CoolDude/testing \;                        \
--irc-channel=#cool-thing  --gitter-room=CoolOrg/thing
```

[Full list of supported options](critter.cr)

The program accepts only named options, and they must be in the form `option=value` (dashes optional, spaces and alternative forms `--option value` forbidden). Normally it bridges only 1 IRC channel with 1 Gitter room but multiple configurations can be supplied: if there is an argument which is a semicolon `;` by itself, it ends one set of options and starts another. Options that are the same as in the previous set don't need to be specified. So the example above bridges *##my-channel* with *CoolDude/testing*, and completely separately *#cool-thing* with *CoolOrg/thing*, which is comparable to just running two separate instances of the program, except then they wouldn't be able to have the same nickname on the same IRC server.

It is not possible to bridge e.g. two IRC channels with this CLI but editing the program to do so is not difficult.

You should sign up for a separate [GitHub][] account for the bot, then sign into [Gitter][] based on it and [get an API key](https://developer.gitter.im/apps). It helps being creative with the bot's nickname, e.g. *FromIRC* and *FromGitter*, so the intent is clear.



[crystal]: http://crystal-lang.org/
[irc]: https://en.wikipedia.org/wiki/Internet_Relay_Chat
[gitter]: https://gitter.im/
[github]: https://github.com/
