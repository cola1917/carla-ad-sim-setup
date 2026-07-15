# Rental Host Preflight

Run this before installing CARLA, ROS, NCore, or NuRec. It distinguishes a
bare-metal/full-VM candidate from a restricted container or Kubernetes Pod and
checks the resources required by this workspace.

Read-only classification:

```bash
bash preflight_host.sh
```

For the proposed single 48 GB GPU host, require at least 45,000 MiB and run the
disposable Docker GPU, bind-mount, and 64 GiB shared-memory probes:

```bash
MIN_GPU_MEMORY_MIB=45000 \
MIN_RAM_GIB=64 \
MIN_DISK_GIB=200 \
bash preflight_host.sh --docker
```

To prove that a modified 48 GB card can really allocate more than 32 GB, use a
PyTorch image already present on the server:

```bash
PYTORCH_TEST_IMAGE=nvcr.io/nvidia/pytorch:26.01-py3 \
MIN_GPU_MEMORY_MIB=45000 \
bash preflight_host.sh --docker --allocate-gib 36
```

`REJECT` is a hard stop. `ACCEPTABLE` means the structural checks passed, not
that CARLA/NuRec are already installed. Review every warning, especially CPU
steal and a Docker daemon that works while local `docker.service` is inactive.

The script is safe to run before setup. Only `--docker` pulls/runs a disposable
CUDA image and creates a temporary bind-mount probe directory.
