FROM cosmwasm/wasmd:latest

COPY docker/config /root/.wasmd/config
COPY artifacts/educhain.wasm /contracts/educhain.wasm
COPY docker/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
