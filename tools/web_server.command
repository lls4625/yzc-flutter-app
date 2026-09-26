#!/bin/zsh
# 以项目根目录的 resources/web 为站点根目录，供 App 下载测试资源。
set -eu

WEB_ROOT="/Users/javalee/work/proj/yzc_f/resources/web"

if ! command -v python3 >/dev/null 2>&1; then
  print -u2 -- "启动失败：未找到 python3，请安装 Python 3 后重试。"
  exit 1
fi

if [[ ! -d "$WEB_ROOT" ]]; then
  print -u2 -- "启动失败：站点目录不存在：$WEB_ROOT"
  exit 1
fi

cd "$WEB_ROOT"

exec python3 -m http.server 8080 --bind 0.0.0.0
