# CheckpointLTC

Shared to do lists inside Roblox Studio. I built it, and I run the server it talks to.

Make a list, share it with your team by code, give teammates edit rights by UserId, and assign lists to people. Lists live on the CheckpointLTC server, not inside your place, so they follow you across places and computers.

The full guide, with every button, setting and limit, is at [checkpointltc.ltclevtec.com/guide.pdf](https://checkpointltc.ltclevtec.com/guide.pdf), or press **Download Guide** at the bottom of the plugin's sidebar.

The code is public so you can see exactly what the plugin and the server do. Questions or problems: [Discord](https://discord.gg/5njkCsBdNd). Security issues: see [SECURITY.md](SECURITY.md).

## What I know about you

* **Your Roblox UserId.** That's how lists know who owns them and who they're shared with.
* **Whether you own the plugin**, if it's a paid version. Roblox answers yes or no when you log in, and again about once a day, since a refund takes the plugin back.
* **Your lists and what's in them.**

That's it. No username, no email, never your password, and nothing from your places.

## How logging in works

Plugins can't open a browser, so login happens on Roblox's site:

1. Press **Log in with Roblox** in the panel. It shows a link and a short code.
2. Open the link, check the code matches the one in Studio, and press **Continue with Roblox**. That's Roblox's own login and permission screen, not mine.
3. Roblox tells my server your UserId (and, for the paid version, whether you own the plugin). The server checks it's the same account that's signed in to Studio.
4. The panel picks it up on its own and gets a private key. That key is saved on your computer with `plugin:SetSetting`, never inside your place. My database only keeps a hash of it.

In the free version the Roblox token is thrown away right after. In the paid version it's kept, encrypted, only so the daily ownership check works. You can remove CheckpointLTC from your Roblox account's connected apps any time, and it'll just ask you to log in again.

You can stay logged in on up to 10 computers. Settings, Devices lists every one and can sign any of them out. Logging in on an eleventh signs out the oldest.

## Who can do what

The server enforces all of this. The plugin can't get around it.

| Action | Owner | Admin | Editor | Viewer | Assigned | Anyone else |
| --- | --- | --- | --- | --- | --- | --- |
| View tasks | yes | yes | yes | yes | yes | no |
| Add, edit, move, delete tasks | yes | yes | yes | no | no | no |
| Check off a task given to you, comment on it | yes | yes | yes | yes | yes | no |
| See share code and people | yes | yes | yes | no | no | no |
| Add or remove people, new code, assign | yes | yes | no | no | no | no |
| Rename, pin to a game, game keys | yes | yes | no | no | no | no |
| Add admins, archive, delete the list | yes | no | no | no | no | no |
| Leave a list or dismiss an assignment | | yes | yes | yes | yes | |

Viewers are people added as viewers and anyone who opened the list with its share code. Admins can't change other admins.

A list you can't see acts like it doesn't exist, so nobody can poke around for list ids. A new share code kicks out everyone who joined with the old one.

Two people editing the same item: whoever saves second gets told someone changed it first and sees their version, so nothing gets silently overwritten.

## Security

* Every id in a URL is random. Every database query is parameterized. Every input is checked and length capped.
* Keys are 256 bit random values, stored only as hashes.
* Rate limits on every request, on login, and per user.
* Item text is escaped before it's shown, so list content can't inject anything.
* The server doesn't serve any files from this repo.

## Looking at the code

```
plugin/      Roblox Studio plugin (Rojo project)
  src/
    Api/     talking to the server: timeouts, retries, key storage
    State/   app state, optimistic updates and rollback
    Ui/      screens and components
worker/      the server: Cloudflare Worker (TypeScript) and D1 database migrations
  src/
    access.ts       the one place roles get decided
    oauth.ts        Log in with Roblox
    licence.ts      paid ownership checks
    routes/         every API endpoint
  migrations/       database schema
  scripts/          permission tests
```

## Only install the official copy

Get CheckpointLTC from its Creator Store page or the link in my [Discord](https://discord.gg/5njkCsBdNd). Reuploaded copies of plugins on the Toolbox sometimes have backdoors added. The official one only ever talks to the CheckpointLTC server and Roblox.

## Licence

You can read this code, but not copy, reupload or sell it. See [LICENSE](LICENSE).
