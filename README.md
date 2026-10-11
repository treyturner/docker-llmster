# docker-llmster

Containerizes LM Studio's [llmster](https://lmstudio.ai/docs/developer/core/headless_llmster).

## Image tags

Two images are published to `ghcr.io` and `forgejo.treyturner.info`:

- Full install (the canonical image)
  - Tagged with the upstream version, e.g. `0.0.12-1`
- A gateway-only image
  - For servers **not participating in inference**
  - Strips out vendor bundles to significantly reduce image size
  - Tagged with a prefixed upstream version, e.g. `gateway-0.0.12-1`

`latest` and `gateway-latest` tags are also available if you too like to live dangerously.

So for the latest **full install**, use one of:

- `ghcr.io/treyturner/llmster`
- `forgejo.treyturner.info/treyturner/llmster`

or for the **gateway-only**, **non-inferencing** image, use either of:

- `ghcr.io/treyturner/llmster:gateway-latest`
- `forgejo.treyturner.info/treyturner/llmster:gateway-latest`

## Security

So as to not bury the lede, `llmster` **does not require authentication by default**. Out of the box, anything that can reach the port can use the API.

🚨 Unless you [enable API token authentication](#enabling-api-token-authentication), only forward traffic from **TRUSTED HOSTS** to this container.

👮 **YOU HAVE BEEN WARNED.** If you don't know what you're doing, **STOP**.

`llmster` ships with a default `BIND_ADDRESS` of `127.0.0.1`. This makes sense for native-OS installations, but in Docker it prevents connections from outside the container. To make this image useful, you'll need to set `BIND_ADDRESS` to `0.0.0.0`, but for the aforementioned reason, this image does **not ship it as the default**.

### Enabling API token authentication

LM Studio 0.4.0 added [API tokens](https://lmstudio.ai/docs/developer/core/authentication), and `llmster` enforces them. The only documented way to turn them on is the desktop app's GUI, and `lms` has no flag for it, so this image does it for you: set `LM_API_TOKEN` and [`start.sh`](start.sh) writes the token into `llmster`'s token store before the server starts.

The token must look like `sk-lm-<8 letters/digits>:<20 letters/digits>`. Generate one with:

```bash
echo "sk-lm-$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8):$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
```

Then pass it to the container as `LM_API_TOKEN`, or mount it as a file and set `LM_API_TOKEN_FILE` (e.g. a Docker secret at `/run/secrets/lm_api_token`). Clients must send it as `Authorization: Bearer sk-lm-…`. The Anthropic-compatible `/v1/messages` endpoint also accepts `x-api-key`. Requests with no token or a bad one get `401`.

Notes:

- Check that it's working by making an unauthenticated request: `curl -i http://<host>:1234/v1/models` should return `401`.
- An invalid `LM_API_TOKEN` stops the container at startup instead of running without authentication.
- Only the token from `LM_API_TOKEN` is managed. Any tokens already in the store (e.g. from a persisted desktop-app config) are kept and still work.
- Changing `LM_API_TOKEN` replaces the managed token. Removing it removes that token, and turns authentication off if no other tokens remain.
- If the server listens on a non-loopback address without authentication, the container logs a warning at startup.
- `lms` inside the container (e.g. `docker exec llmster lms ls`) authenticates separately and keeps working.
- The token store (`permissions-store.json` in the persisted `internal` volume) isn't documented by LM Studio. Its format was worked out from `llmster` 0.0.25-1 and may change in a future release. If the format changes, `llmster` may silently fall back to no authentication, so use the `curl` check above after upgrading.

Even with tokens enabled, traffic is plain HTTP. Put a TLS-terminating reverse proxy in front of the container before exposing it beyond a trusted network.

## Volume mounts

Persist data in these paths using named or host-mounted volumes.

| Container Path              | Description          |
| --------------------------- | -------------------- |
| `/root/persist/credentials` | Credential store\*   |
| `/root/persist/internal`    | Configuration data\* |

\*Persistence of data from LM Studio's _actual_ paths (`/root/.lmstudio/credentials` and `/root/.lmstudio/.internal`) is managed by [`start.sh`](start.sh).

## Environment variables

| Variable              | Description                                                                                          | Default                |
| --------------------- | ---------------------------------------------------------------------------------------------------- | ---------------------- |
| `BIND_ADDRESS`        | ⚠️ **[DANGEROUS](#security).** Set `0.0.0.0` to listen on all interfaces.                            | `127.0.0.1`            |
| `ENABLE_CORS`         | Set `1` to allow any website you visit to access the server. Required if you're developing a web app | `0`                    |
| `LISTEN_PORT`         | Will use the port from the prior invocation if not supplied                                          | `1234` _(if no prior)_ |
| `LM_API_TOKEN`        | If set, require this [API token](#enabling-api-token-authentication) for all API requests            | _(no authentication)_  |
| `LM_API_TOKEN_FILE`   | Path to a file containing the API token. Used when `LM_API_TOKEN` is unset                           |                        |
| `LM_LINK_DEVICE_NAME` | If set, used as the LM Link device name                                                              | _(container hostname)_ |

## Regarding `SIGINT`

The startup script starts the service and then runs `exec tail` to stream the newest log. In order for `lms` to respect `Ctrl-C`/`SIGINT`, you must start the container with `--init`.

## Usage

Putting it all together, here's how to run via command-line:

```bash
docker run \
  --rm -it --init \
  --name llmster \
  --hostname slartibartfast \
  -p "1234:1234" \
  -e BIND_ADDRESS=0.0.0.0 \
  -e LM_API_TOKEN=sk-lm-REPLACE_ME \
  -v /mnt/cache/appdata/llmster/credentials:/root/persist/credentials \
  -v /mnt/cache/appdata/llmster/internal:/root/persist/internal \
  ghcr.io/treyturner/llmster
```

Or here's an example `docker-compose.yml`:

```yaml
services:
  llmster:
    image: ghcr.io/treyturner/llmster
    container_name: llmster
    hostname: zaphod
    restart: unless-stopped
    init: true
    environment:
      BIND_ADDRESS: "0.0.0.0"
      LM_API_TOKEN: "sk-lm-REPLACE_ME"
    ports:
      - "1234:1234"
    volumes:
      - /mnt/cache/appdata/llmster/credentials:/root/persist/credentials
      - /mnt/cache/appdata/llmster/internal:/root/persist/internal
```

### GPU passthrough (full image only)

To offload inference to a GPU, pass the device(s) through to the container.

**NVIDIA** requires the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) on the host:

```bash
# cli
docker run ... --gpus all ghcr.io/treyturner/llmster
```

```yaml
# docker-compose.yml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

For **AMD**, pass the ROCm render nodes through directly:

```bash
docker run ... --device /dev/kfd --device /dev/dri ghcr.io/treyturner/llmster
```

```yaml
# docker-compose.yml
devices:
  - /dev/kfd
  - /dev/dri
```

## Logging in to LM Link

Login from **outside the container** using:

```bash
docker exec -it llmster lms login
```

or from **inside the container** using:

```bash
lms login
```

## Build args

| Variable       | Description                                     | Default |
| -------------- | ----------------------------------------------- | ------- |
| `GATEWAY_ONLY` | Set to `1` to strip vendor bundles during build | `0`     |

Therefore, to build the full image:

```bash
docker build -t local/treyturner/llmster .
```

or the gateway image:

```bash
docker build --build-arg GATEWAY_ONLY=1 \
    -t local/treyturner/llmster:gateway-latest .
```
