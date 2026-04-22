FROM debian:bookworm-slim
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG GATEWAY_ONLY=0

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      coreutils \
      curl \
      libatomic1 \
      libgomp1

WORKDIR /root

RUN curl -fsSL -o /tmp/install.sh https://lmstudio.ai/install.sh \
    && chmod +x /tmp/install.sh \
    && /tmp/install.sh \
    && rm -f /tmp/install.sh \
    && basename "$(find /root/.lmstudio/llmster -mindepth 1 -maxdepth 1 -type d)" > /root/version \
    && if [[ "${GATEWAY_ONLY}" == "1" ]]; then \
        rm -rf /root/.lmstudio/llmster/$(cat /root/version)/.bundle/bin/extensions/backends/llama* \
            /root/.lmstudio/llmster/$(cat /root/version)/.bundle/bin/extensions/backends/vendor/linux-llama*; \
    fi

COPY --chmod=755 start.sh /root/start.sh

ENV PATH=${PATH}:/root/.lmstudio/bin
CMD ["/root/start.sh"]
