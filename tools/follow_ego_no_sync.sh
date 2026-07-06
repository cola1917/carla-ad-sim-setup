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
spectator = world.get_spectator()

print("Waiting for ego vehicle...")
vehicle = None
while vehicle is None:
    for actor in world.get_actors().filter("vehicle.*"):
        if actor.attributes.get("role_name") == "hero":
            vehicle = actor
            break
    if vehicle is None:
        print("  hero vehicle not found yet. Retrying...")
        time.sleep(1)

print(f"Found ego vehicle: {vehicle.type_id} (id={vehicle.id})")
print("Following... Press Ctrl+C to stop.")


def on_tick(_snapshot):
    if vehicle.is_alive:
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


world.on_tick(on_tick)

try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    print("\nStopped.")
EOF
