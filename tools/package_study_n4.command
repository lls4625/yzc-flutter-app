#!/bin/zsh
# 双击打包 database/study 下 n4 到 resources/web/study，并更新 SHA-256。
set -eu
resource_dir="${0:A:h}"
exec python3 "$resource_dir/package_study_resources.py" n4
