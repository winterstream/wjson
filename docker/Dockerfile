FROM alpine:latest

LABEL org.opencontainers.image.title="wjson Benchmark Arena" \
      org.opencontainers.image.description="Interactive head-to-head benchmark arena pitting pure Lua JSON parsers against C extensions" \
      org.opencontainers.image.url="https://github.com/winterstream/wjson" \
      org.opencontainers.image.source="https://github.com/winterstream/wjson" \
      org.opencontainers.image.licenses="MIT"

# Install LuaJIT, Lua 5.4, Lua 5.5, C modules, and tools
RUN apk add --no-cache \
      luajit \
      lua5.1-cjson \
      lua5.1-lpeg \
      lua5.4 \
      lua5.4-cjson \
      lua5.4-lpeg \
      lua5.5 \
      lua5.5-cjson \
      lua5.5-lpeg \
      luarocks5.1 \
      git \
      gzip && \
    luarocks-5.1 --lua-version=5.1 install lunajson && \
    apk del luarocks5.1 git && \
    rm -rf /root/.cache /tmp/*

WORKDIR /app

# Copy library and benchmark code
COPY src/ /app/src/
COPY bench/dkjson.lua /app/bench/dkjson.lua
COPY bench/rxi_json.lua /app/bench/rxi_json.lua
COPY spec/datasets/ /app/spec/datasets/
COPY docker/arena.lua /app/arena.lua
COPY docker/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENV LUA_PATH="/app/?.lua;/app/src/?.lua;/app/src/?/init.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;;"
ENV LUA_CPATH="/usr/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/?.so;;"

ENTRYPOINT ["/entrypoint.sh"]
