# Download CARLA 0.9.16

The official Ubuntu archive is linked by the CARLA 0.9.16 GitHub release:

- Release: <https://github.com/carla-simulator/carla/releases/tag/0.9.16>
- Linux archive redirect: <https://tiny.carla.org/carla-0-9-16-linux>

Download before running Stage 3:

```bash
bash download_carla.sh
bash stage3_carla.sh
```

The downloader writes to `CARLA_TAR_FILE` from `env_config.sh`, resumes an
interrupted `.part` file, validates the gzip/tar structure, and records a local
SHA-256 file. An already valid archive is reused.

To discard an invalid or unwanted archive and download from the beginning:

```bash
bash download_carla.sh --force
```

The script is intentionally frozen to CARLA 0.9.16 so that the simulator,
Python API, ScenarioRunner, and ClosedLoopBench evidence use one version.
