FROM cosmwasm/wasmd:v0.45.0

RUN apk update && apk add --no-cache dos2unix curl jq moreutils
COPY docker/config /root/.wasmd/config
COPY artifacts/educhain.wasm /contracts/educhain.wasm
COPY docker/entrypoint.sh /bin/entrypoint.sh
RUN dos2unix /bin/entrypoint.sh && chmod +x /bin/entrypoint.sh
ENTRYPOINT ["/bin/entrypoint.sh"]
