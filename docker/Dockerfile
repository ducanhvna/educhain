FROM cosmwasm/wasmd:v0.50.0

RUN apk update && apk add --no-cache curl jq moreutils dos2unix
COPY docker/config /root/.wasmd/config
COPY artifacts/educhain.wasm /contracts/educhain.wasm
COPY docker/entrypoint.sh /bin/entrypoint.sh
RUN dos2unix /bin/entrypoint.sh && chmod +x /bin/entrypoint.sh
ENTRYPOINT ["/bin/entrypoint.sh"]
