FROM cosmwasm/wasmd:v0.50.0

RUN apk update && apk add --no-cache curl jq moreutils dos2unix
# Install bech32 from source (official C reference implementation)
RUN apk add --no-cache build-base git \
    && git clone https://github.com/sipa/bech32.git /tmp/bech32 \
    && cd /tmp/bech32/ref/c \
    && gcc -o bech32 *.c \
    && mv bech32 /usr/local/bin/ \
    && cd / \
    && rm -rf /tmp/bech32 \
    && apk del build-base git
COPY docker/config /root/.wasmd/config
COPY artifacts/educhain.wasm /contracts/educhain.wasm
COPY docker/entrypoint.sh /bin/entrypoint.sh
RUN dos2unix /bin/entrypoint.sh && chmod +x /bin/entrypoint.sh
ENTRYPOINT ["/bin/entrypoint.sh"]
