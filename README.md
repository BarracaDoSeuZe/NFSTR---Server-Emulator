# NFS The Run Private Server

A private server for **Need for Speed: The Run (PC)**. It brings back the
online features EA shut down: login, Autolog (profile, friends, speedwalls,
recommendations, news), photo sharing, groups, invites and online playlists
on dedicated race servers.

> The repository contains no game files, no EA binaries and no prebuilt
> executables. You need your own copy of the game (PC 1.1.0.0). Not affiliated
> with or endorsed by Electronic Arts.

## Contents

```text
source/            Go: server (cmd/nfsrun-server), player launcher (cmd/nfsrun-launcher)
legacy_gateway/    C: SSLv3 gateway for the game's Redirector and web Autolog connections
scripts/           first-run setup, server start, player package
tools/             optional exe patches, firewall helper, Blaze schema generator
client_config/     Util.fetchClientConfig sections
data/              news, legal texts, playlist pool (runtime data is created here)
docs/              documentation
launcher/          player documentation and third-party notice
mariadb/           put a portable MariaDB here
```

## Host a server

### What you need

- Windows x64 with the game installed (the server runs it as the race servers)
- a portable MariaDB, extracted to `mariadb\` (`mariadb\bin\mariadbd.exe`)
- a short domain (16 characters at most) whose names point at the server:
  `nfs.`, `scert-nfs.`, `stest-nfs.` and `redirector.` + your domain
- to build: Go 1.23+, Visual Studio Build Tools (C++ x86), Perl, and internet
  access on the first build (the gateway build downloads OpenSSL 1.0.2u and
  checks its SHA-256)

### Steps

1. Run `Build_All.bat`. It tests and builds `nfsrun-server.exe`,
   `launcher\nfsrun-launcher.exe` and `legacy_gateway\build\nfsrun-ssl-gateway.exe`.
2. Run `start_server.bat`. The first start asks for:

   | Question | Example | Notes |
   |---|---|---|
   | DB port / user / password / name | `1979` / `NFSRunServer` / blank / `NFSRun` | blank password = generated |
   | Game folder | `C:\Games\NFS The Run` | blank = no race servers |
   | Base domain | `example.org` | the domain of the four host names above |
   | Public IPv4 | `203.0.113.10` | the server's public address |
   | Launcher address behind Cloudflare | blank | blank = direct HTTPS; see [LAUNCHER_HTTPS.md](docs/LAUNCHER_HTTPS.md) |

   It writes `config\`, the certificates in `certs\`, the database in
   `mariadb\data\` and the player package `dist\NFSTR_Client.zip`.
3. Open the [ports](#ports) in the Windows firewall and in your router or
   hosting panel.
4. For each player, type `C` in the server window, then `invite <name>`. Send
   the player the package and their code.

Later starts only run `start_server.bat`; `stop_server.bat` (or `Q` then `Y`
in the server window) stops everything.

### Server window

`C` (or `/`) opens a command line; changes ask before they happen.

| Command | Does |
|---|---|
| `players`, `players all` | who is online, and where / every player |
| `games` | games, race servers and the address players get |
| `invite <name> [hours]` | one-time invite code for a new player (12 h) |
| `invites`, `invites cancel <name>` | pending codes |
| `reset-key <name>` | the player lost their key: new invite code, records kept |
| `kick <name>` | disconnect a player |
| `rename <old> <new>` | new name, same records |
| `delete-player <name>` | delete a player and all their data |
| `package` | rebuild the player package |

### Scripts

| Script | Purpose |
|---|---|
| `Build_All.bat` | test and build everything |
| `build_launcher.bat` | build only the launcher |
| `start_server.bat` | first-run setup, then start MariaDB, gateway and server |
| `stop_server.bat` | stop the server cleanly |
| `show_records.bat` | print the leaderboard records |
| `reset_setup.bat` | delete `config\`, the certificate and the database (asks first) |
| `scripts\make_client_package.ps1` | rebuild the player package |

### Ports

| Protocol | Port | Purpose |
|---|---:|---|
| TCP | 42127 | Redirector (SSLv3) |
| TCP | 10041 | Blaze |
| TCP | 8443 | launcher (HTTPS) |
| TCP | 18080 | photos (HTTP) |
| TCP | 18443 | web Autolog (SSLv3) |
| UDP | 6100-6163 | race relay |

`tools\open_ds_firewall.bat` opens the relay range. The race servers' own
ports stay on 127.0.0.1.

## Play

Players need the game (PC 1.1.0.0) and the package from the server owner:

1. Copy the package into the game folder.
2. Start `nfsrun-launcher.exe` once; it creates `nfsrun-launcher.ini`. Set
   `PLAYER_NAME` and the `INVITE_CODE` from the server owner there.
3. Start the launcher again and press **PLAY**.

The launcher has the server built in and prepares its own copy of the game
(`NFSTR_lsx3216.exe`); the original game files are not changed. It asks
once before it changes anything. See [launcher/README.txt](launcher/README.txt).

## How it works

- **Login.** The launcher keeps a private Ed25519 key (`nfsrun-launcher.key`)
  and proves it to the server over HTTPS; the server stores only the public
  key. The game logs in with one-time codes, so nothing reusable travels on
  its unencrypted connections. See [docs/LOGIN.md](docs/LOGIN.md).
- **Origin.** The game needs Origin; the launcher answers the game's Origin
  SDK locally and relays friends, presence and invites. See
  [docs/ORIGIN_LSX.md](docs/ORIGIN_LSX.md).
- **Races.** Online races ran on EA's dedicated servers. The game exe still
  contains the server mode, so the server runs copies of it as race servers.
  See [docs/MULTIPLAYER_DEDICATED.md](docs/MULTIPLAYER_DEDICATED.md).

## Documentation

| Document | Contents |
|---|---|
| [CONFIGURATION.md](docs/CONFIGURATION.md) | every setting, file, command and command-line option |
| [LOGIN.md](docs/LOGIN.md) | launcher login, invites, lost keys |
| [LAUNCHER_HTTPS.md](docs/LAUNCHER_HTTPS.md) | launcher HTTPS: direct certificate or Cloudflare |
| [ORIGIN_LSX.md](docs/ORIGIN_LSX.md) | the launcher, local Origin, friends and invites |
| [MULTIPLAYER_DEDICATED.md](docs/MULTIPLAYER_DEDICATED.md) | matchmaking, race servers, relay, playlists |
| [AUTOLOG.md](docs/AUTOLOG.md) | Autolog, web Autolog, news, photos |
| [CLIENT_PATCHING.md](docs/CLIENT_PATCHING.md) | supported game build and every exe patch |
| [LEGACY_PROTOSSL.md](docs/LEGACY_PROTOSSL.md) | SSLv3 gateway and certificate |
| [BLAZE_PROTOCOL.md](docs/BLAZE_PROTOCOL.md) | Blaze wire format and components |
| [BLAZE_API.md](docs/BLAZE_API.md) | generated list of every Blaze RPC and type |
| [TOOLS.md](docs/TOOLS.md) | tools in `tools\` |

## Security

The game's own connections cannot be secured: Blaze is plaintext and the
Redirector and web Autolog use SSLv3, because the 2011 client only speaks
those. Only the launcher uses modern HTTPS. Keep backend ports on 127.0.0.1
and expose only the ports above. Never publish `config\`, `certs\`,
`mariadb\data\`, logs or a player's `nfsrun-launcher.key`. See
[SECURITY.md](SECURITY.md).

## Project status

A hobby project, written for fun and out of curiosity, largely with AI
assistance. It is published as is and archived: no support, no roadmap, no
official instance. It is meant for small private servers among friends, not
for large public services. Logs and the database hold player names and IP
addresses; if you run it for other people, you are responsible for that
server.

## Credits

- **EAappEmulater** by Misaka_Mikoto_01, CrazyZhang666 and B1397KB
  (<https://github.com/CrazyZhang666/EAappEmulater>, MIT): the launcher's
  LSX handshake and crypto are a Go port of parts of it; see
  `launcher\THIRD_PARTY_NOTICES.txt`.
- **NFSTR LAN Script** by Hypercycle, And799 and mRally2 (nfsmods.xyz): showed
  how the game runs as a dedicated server and which arguments a race server
  needs.
- **OpenSSL 1.0.2u**: built by the gateway build, not part of the repository.
- Reverse engineering with **Ghidra**, **Capstone** and **Unicorn**.

## License

MIT, see [LICENSE.md](LICENSE.md). Provided without warranty.
