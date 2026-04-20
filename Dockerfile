FROM debian:bookworm-slim
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG LLMSTER_GATEWAY_ONLY=0
ENV LLMSTER_GATEWAY_ONLY=${LLMSTER_GATEWAY_ONLY}

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      libatomic1 \
      libgomp1

WORKDIR /root

RUN curl -fsSL -o /tmp/install.sh https://lmstudio.ai/install.sh \
  && chmod +x /tmp/install.sh \
  && /tmp/install.sh \
  && rm -f /tmp/install.sh \
  && printf '%s' "$(basename $(dirname $(find /root/.lmstudio -type f -name llmster)))" > /root/.lmstudio/.version \
  && if [[ "${LLMSTER_GATEWAY_ONLY}" = "1" ]]; then \
    rm -rf /root/.lmstudio/llmster/$(cat /root/.lmstudio/.version)/.bundle/bin/extensions/backends/llama* \
      /root/.lmstudio/llmster/$(cat /root/.lmstudio/.version)/.bundle/bin/extensions/backends/vendor/linux-llama*; \
    fi \
  && ln -sf "/root/.lmstudio/llmster/$(cat /root/.lmstudio/.version)/llmster" /usr/local/bin/llmster

VOLUME ["/root/.lmstudio/credentials"]
ENTRYPOINT ["/usr/local/bin/llmster"]
CMD ["server", "start"]
