# packages/

Companion projects that live alongside the Lanyard server. They are kept out of
the Elixir application at the repo root — the root `mix` project never sees this
directory, and each package keeps its own toolchain, dependencies and lockfile.
The root `Dockerfile` does build from here, assembling every service into one
image.

| Package | Stack | What it is |
| --- | --- | --- |
| [`graphql/`](./graphql) | TypeScript, Apollo Server | GraphQL gateway in front of the Lanyard REST API. Listens on `:8080`, served at `/graphql` in the all-in-one image. |
| [`profile-readme/`](./profile-readme) | Next.js 15, React 19, Bun | Renders your presence as an image for a GitHub profile README. Listens on `:3000`, served at `/readme` in the all-in-one image. |
| [`mcp-server/`](./mcp-server) | Python 3.11, FastMCP | MCP server so AI assistants can read Lanyard presences. Speaks stdio, or HTTP when `MCP_TRANSPORT` is set. |
| [`js-lanyard/`](./js-lanyard) | Vanilla JS | Browser client for the REST API and WebSocket, no build step. |
| [`use-listen-along/`](./use-listen-along) | TypeScript, React | Hook that keeps Spotify playback in sync with another user's presence. |
| [`osu-nowplaying/`](./osu-nowplaying) | PowerShell | Pushes your current osu! beatmap into the Lanyard KV store. |

Each package keeps its original README with full usage docs.

## Pointing a package at your own server

Every package defaults to the public instance at `https://api.lanyard.rest`. To
run them against a self-hosted server instead:

| Package | How |
| --- | --- |
| `graphql` | `LANYARD_API_URL` env var |
| `profile-readme` | `LANYARD_API_URL` env var |
| `mcp-server` | `LANYARD_API_URL` env var |
| `use-listen-along` | 4th argument: `useListenAlong(id, auth, disconnect, 'https://lanyard.example.com')` |
| `js-lanyard` | `apiUrl` / `websocketUrl` options: `lanyard({ userId, apiUrl: 'https://lanyard.example.com/v1' })` |

In every case the URL is the server root without a trailing slash (`/v1` is
appended for you), except `js-lanyard`, whose `apiUrl` includes `/v1`.

The repo-root `Dockerfile` builds **all of these into a single image** that runs
them in one container behind one port - see
[Running the whole stack](../README.md#running-the-whole-stack). There are no
per-package images to build; `packages/mcp-server/Dockerfile` is kept from its
original repository for anyone who wants to run that server on its own.

Inside that image the API is at the root, `graphql` at `/graphql`,
`profile-readme` at `/readme` and `mcp-server` at `/mcp`. Routing lives in the
repo-root `Caddyfile`, and `docker/entrypoint.sh` decides which services start.

Two packages take extra configuration there:

- `profile-readme` reads `NEXT_BASE_PATH` so it can be mounted under a prefix;
  the image builds it with `/readme`. Leave it unset to serve at the root.
- `mcp-server` reads `MCP_TRANSPORT` (`stdio`, the default, or
  `streamable-http`/`sse`) plus `MCP_HOST`/`MCP_PORT`. The image uses
  `streamable-http` so the server is reachable over the shared port; local
  assistants that spawn the process themselves should keep `stdio`.

## Working on a package

```sh
cd packages/graphql        && npm install && npm run dev
cd packages/profile-readme && bun install && bun run dev
cd packages/mcp-server     && pip install -r requirements.txt && python lanyard_server.py
cd packages/use-listen-along && yarn install && yarn start
```

Note: some packages carry a `.github/workflows/` directory from their original
repository. GitHub only reads workflows from the repository root, so these are
inert here and kept for reference only.
