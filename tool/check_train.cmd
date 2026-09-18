@echo off
cd /d C:\Users\amake\Claude\Projects\aori_shogi\python
.venv-train\Scripts\python.exe -c "import torch,transformers,peft,trl,datasets;print('torch',torch.__version__);print('cuda',torch.cuda.is_available());print('gpu',torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'none');print('transformers',transformers.__version__);print('peft',peft.__version__);print('trl',trl.__version__)"
