# notify

One place every alert goes through: an [Apprise API](https://github.com/caronc/apprise-api)
container. Sources post a text and a tag, the gateway fans it out to the
channels that carry that tag. Channels are Apprise URLs and live in the private
chezmoi toml (`[[data.notify.channels]]`), so adding Discord or mail later is one
entry there, not a change in any stack.

    notify/
      compose.yaml          apprise-api, key "homelab"
      config/homelab.yml    channels + tags (gitignored, rendered by dotfiles, see below)

## Tags

- `primary` — the everyday channel (Telegram).
- `fallback` — tried by the senders when `primary` reports a delivery failure.
- `critical` — attached to every channel: one post reaches them all.

Apprise itself does not retry: one attempt per channel, HTTP 424 when any
channel failed or no channel carries the tag. The `primary → fallback` order is
the sender's job (see `notify` on the laptops and `notify()` in cloud-sync).

## Sending

Inside docker (every stack on the `proxy` network):

    curl -sS --data-urlencode "body=disk 95%" --data-urlencode "title=[host] cloud" \
        --data-urlencode "tag=primary" http://notify:8000/notify/homelab

From a laptop the same URL on the host port (`PORT`), wrapped by `~/.local/bin/notify`
from dotfiles: `notify -t "title" text`, `notify -g critical text`, text from stdin.
Optional fields: `type=info|success|warning|failure`, `format=text|markdown|html`.

## Config

`config/homelab.yml` is host-side like `rclone.conf`: gitignored, protected from
`make deploy`, rendered by dotfiles from the toml into
`~/.config/homelab/notify/config/homelab.yml` (secrets come from `passp` at
`chezmoi apply`, placeholders `{{passp:NAME}}` in the toml), copied into the
tree by make and shipped with `make secrets.push`. `APPRISE_CONFIG_LOCK=yes`
hides the config from the web UI; the container never writes it.

Adding a channel: a `[[data.notify.channels]]` entry (name, Apprise URL, tags),
the secret in `passp`, then `chezmoi apply && make secrets.push && make restart.notify`.

## Setup

1. `cp .env.example .env` or let dotfiles render it (`[data.homelab.notify]`).
2. Telegram: bot via @BotFather, a private channel or group with the bot in it,
   chat id from `curl https://api.telegram.org/bot<TOKEN>/getUpdates` after one
   message; `passp insert im/telegram.org/homelab-notify-bot` with the token, the chat id into
   the `tgram://` URL in the toml.
3. `make deploy && make secrets.push && make networks && make up.notify`, then a
   test post as above.
