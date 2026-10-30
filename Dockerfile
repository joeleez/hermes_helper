# 在官方映像上加一層：Feishu (Lark) 依賴
#
# 為什麼需要這層：
#   官方映像內建 feishu 平台插件（/opt/hermes/plugins/platforms/feishu），
#   但沒有它的 Python 依賴 lark_oapi，gateway 啟動時會報
#   「Platform 'Feishu / Lark' requirements not met」然後 adapter creation failed。
#
#   直接 docker exec pip install 會在容器重建時消失，所以寫成映像層，
#   讓「重建 = 可重現」，也留在版本控制裡。

FROM nousresearch/hermes-agent:stable

USER root

# 映像的 venv 由 uv 建立，沒有 pip；先用 ensurepip 補上
RUN /opt/hermes/.venv/bin/python -m ensurepip --upgrade >/dev/null 2>&1 \
 && /opt/hermes/.venv/bin/python -m pip install --no-cache-dir --quiet lark-oapi pyyaml \
 && /opt/hermes/.venv/bin/python -c "import lark_oapi, yaml; print('lark_oapi + pyyaml ready')"

# 回到映像預設使用者（官方 entrypoint 會處理 s6 與降權）
USER root
