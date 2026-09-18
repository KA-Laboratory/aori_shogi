@echo off
rem 学習用の環境を作る（Windows のまま。4bit 量子化は使わないので bitsandbytes は要らない）
setlocal
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
echo == disk ==
dir C:\ | find "bytes free"
echo == create venv ==
uv venv .venv-train --python 3.12
echo == torch (CUDA) ==
uv pip install --python .venv-train torch --torch-backend=auto
echo == libs ==
uv pip install --python .venv-train transformers peft trl datasets accelerate
echo == check ==
.venv-train\Scripts\python.exe -c "import torch;print('torch',torch.__version__,'cuda',torch.cuda.is_available(),torch.cuda.get_device_name(0) if torch.cuda.is_available() else '')"
echo SETUP_DONE
