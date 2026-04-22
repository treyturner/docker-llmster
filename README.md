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

So as to not bury the lede, `llmster` **does not yet appear to support** configuration of API tokens for gating API access.

🚨 Therefore you must only forward traffic from **TRUSTED HOSTS** to this container as there is currently **NO ACCESS CONTROL**.

👮 **YOU HAVE BEEN WARNED.** If you don't know what you're doing, **STOP**.

`llmster` ships with a default `BIND_ADDRESS` of `127.0.0.1`. This makes sense for native-OS installations, but in Docker it prevents connections from outside the container. To make this image useful, you'll need to set `BIND_ADDRESS` to `0.0.0.0`, but for the aforementioned reason reason, this image does **not ship it as the default**.

As soon as `llmster` supports configuration of API keys, that functionality will be wired into this image to the extent possible.

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
