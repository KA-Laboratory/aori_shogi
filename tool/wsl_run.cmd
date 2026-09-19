@echo off
rem WSL 側のスクリプトを走らせる: wsl_run.cmd <name>  → tool/wsl/<name>.sh
wsl -e bash /mnt/c/Users/amake/Claude/Projects/aori_shogi/tool/wsl/%1.sh
