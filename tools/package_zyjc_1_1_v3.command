#!/bin/zsh
# 将已编辑的 V3 初级上册资源打包到 web；不重新匹配或修改源数据库。
set -eu
resource_dir="${0:A:h}"
exec python3 "$resource_dir/package_resources.py" --v3 zyjc_1_1
