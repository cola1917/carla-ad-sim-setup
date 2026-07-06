#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env_config.sh"

export CARLA_HOST="${CARLA_HOST:-localhost}"
export CARLA_PORT

python - <<'EOF'
import math
import os
import time

import carla


client = carla.Client(os.environ["CARLA_HOST"], int(os.environ["CARLA_PORT"]))
client.set_timeout(10)
world = client.get_world()

settings = world.get_settings()
settings.synchronous_mode = True
settings.fixed_delta_seconds = 0.05
world.apply_settings(settings)

spectator = world.get_spectator()

print("Waiting for ego vehicle...")
vehicle = None
while vehicle is None:
    world.tick()
    for actor in world.get_actors().filter("vehicle.*"):
        if actor.attributes.get("role_name") == "hero":
            vehicle = actor
            break
    if vehicle is None:
        print("  hero vehicle not found yet...")
        time.sleep(0.5)

print(f"Found ego vehicle: {vehicle.type_id} (id={vehicle.id})")
print("Following... Press Ctrl+C to stop.")

try:
    while True:
        world.tick()
        transform = vehicle.get_transform()
        yaw = math.radians(transform.rotation.yaw)
        x = transform.location.x - 8 * math.cos(yaw)
        y = transform.location.y - 8 * math.sin(yaw)
        z = transform.location.z + 3
        spectator.set_transform(
            carla.Transform(
                carla.Location(x, y, z),
                carla.Rotation(pitch=-15, yaw=transform.rotation.yaw),
            )
        )
except KeyboardInterrupt:
    settings.synchronous_mode = False
    world.apply_settings(settings)
    print("\nStopped.")
EOF
