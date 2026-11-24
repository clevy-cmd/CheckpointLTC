# Security

Found a way to see or change lists you shouldn't, log in as someone else, or anything like that? Report it privately, either way works:

* **On GitHub:** the **Security** tab of this repo → **Report a vulnerability**. Only I can see it.
* **On Discord:** https://discord.gg/5njkCsBdNd. DM me, don't post it in a public channel.

Keeping it private means it gets fixed before anyone else can use it.

Worth knowing before you dig in: the code being public doesn't make it less safe. Nothing secret lives in this repo. The Roblox OAuth secret is a Cloudflare Worker secret, user keys are only stored as hashes, and every permission is checked on the server.
