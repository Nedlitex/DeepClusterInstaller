# Install the DeepCluster worker
---
## 1. Prerequisites
#### Operating System:
  We recommand running the DeepCluster Worker with [Ubuntu 18.04 LTS](http://releases.ubuntu.com/18.04/).

#### NVIDIA&reg; GPU:
  We require NVIDIA&reg; GPUs with CUDA&reg; compatibility 3.5 or higher. Please refer to [this document](https://developer.nvidia.com/cuda-gpus) to determine if your GPU satisfies the requirement.

#### NVIDIA&reg; GPU driver:
  We require [NVIDIA&reg; GPU driver](https://www.nvidia.com/Download/index.aspx?lang=en-us) 396.x or higher.
  > Hint: Run the command 'nvidia-smi' from terminal, you should see output similiar to this

       +-----------------------------------------------------------------------------+
       | NVIDIA-SMI 410.104      Driver Version: 410.104      CUDA Version: 10.0     |
       |-------------------------------+----------------------+----------------------+
       | GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
       | Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
       |===============================+======================+======================|
       |   0  GeForce GTX 970     On   | 00000000:05:00.0 Off |                  N/A |
       | 31%   27C    P8    14W / 170W |      1MiB /  4043MiB |      0%      Default |
       +-------------------------------+----------------------+----------------------+

       +-----------------------------------------------------------------------------+
       | Processes:                                                       GPU Memory |
       |  GPU       PID   Type   Process name                             Usage      |
       |=============================================================================|
       |  No running processes found                                                 |
       +-----------------------------------------------------------------------------+

  > *Important*: [Persistence Mode](https://docs.nvidia.com/deploy/driver-persistence/index.html#usage) is required to use GPU inside container. You can enable it using the command 'sudo nvidia-smi -pm 1' or start the [Persistence Daemon on boot](https://docs.nvidia.com/deploy/driver-persistence/index.html#installation).
## 2. Dependencies

#### Anaconda
  We use Anaconda to manage the worker environment.
  > Installer will install [Miniconda](https://docs.conda.io/projects/continuumio-conda/en/latest/user-guide/install/linux.html).

#### Docker
  We use Docker to isolate the user's code from the host environment.
  > Installer will install [Docker CE](https://docs.docker.com/install/linux/docker-ce/ubuntu/).

#### NVIDIA&reg; Docker Runtime
  We use [NVIDIA&reg; Docker Runtime](https://github.com/NVIDIA/nvidia-docker) for using GPU inside container.
  > Installer will install NVIDIA&reg; Docker Runtime.

## 3. Install the DeepCluster Worker Package
  Download the [installer.sh](www.placeholder.com/ubuntu/installer.sh)
  > wget "www.placeholder.com/ubuntu/installer.sh"

  Run the installer script
  > sudo ./installer.sh -y

  For more information, run
  > ./installer.sh -h