"""
Automation engine — moves trains through the layout automatically.

Each active train runs its own asyncio task that:
  1. Waits for its current block to clear (s88 feedback)
  2. Checks the next block is free and signal is green
  3. Accelerates to cruising speed
  4. Begins braking at the decel distance before a station
  5. Stops precisely at the platform, waits the dwell time
  6. Repeats around the route (loops if configured)

Block occupancy is detected via s88 sensors wired into the CS3+.
If you don't have s88 sensors yet, set USE_TIMED_BLOCKS = True and
the engine will estimate position by time + speed instead.
"""

from __future__ import annotations
import asyncio
import logging
from typing import Optional

from .cs3_client import CS3PlusClient, FORWARD
from .layout import Layout, Block, TrainConfig
from .notify import notify

logger = logging.getLogger(__name__)

# Set True if you don't have s88 feedback sensors yet.
# The engine will estimate positions using speed and time instead.
USE_TIMED_BLOCKS = False

# Poll interval for s88 sensors (seconds)
SENSOR_POLL_HZ = 0.25

# Speed step used for gentle braking approach into stations
APPROACH_SPEED = 20


class TrainRunner:
    """Drives one train around a route autonomously."""

    def __init__(
        self,
        train: TrainConfig,
        route_block_ids: list[str],
        layout: Layout,
        cs3: CS3PlusClient,
        loop_route: bool = True,
    ):
        self.train = train
        self.route_block_ids = route_block_ids
        self.layout = layout
        self.cs3 = cs3
        self.loop_route = loop_route
        self._running = False
        self._current_block_index = 0
        self._task: Optional[asyncio.Task] = None

    def start(self):
        self._running = True
        self._task = asyncio.create_task(self._run(), name=f"train_{self.train.id}")
        logger.info("Started automation for %s (addr %d)", self.train.name, self.train.dcc_address)

    async def stop(self):
        self._running = False
        await self.cs3.stop_loco(self.train.dcc_address)
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _run(self):
        addr = self.train.dcc_address
        block_ids = self.route_block_ids

        # Turn on headlights (F0)
        await self.cs3.set_loco_function(addr, 0, True)

        idx = 0
        while self._running:
            current_id = block_ids[idx % len(block_ids)]
            next_idx = (idx + 1) % len(block_ids)
            next_id = block_ids[next_idx]

            current_block = self.layout.blocks.get(current_id)
            next_block = self.layout.blocks.get(next_id)

            if not current_block or not next_block:
                logger.error("Unknown block in route: %s or %s", current_id, next_id)
                break

            # Mark current block occupied
            current_block.occupied_by = self.train.id
            await self._update_signal_for_block(current_id, occupied=True)

            if current_block.is_station:
                await self._station_stop(current_block)
            else:
                # Running block — wait until we've traversed it
                await self._traverse_block(current_block, next_block)

            # Check next block is free before entering
            await self._wait_for_block_clear(next_block)

            # Set signal green for next block entry
            await self._update_signal_for_block(next_id, occupied=False)

            # Release current block
            current_block.occupied_by = None
            await self._update_signal_for_block(current_id, occupied=False)

            if not self.loop_route and next_idx == 0:
                # End of route, stop train
                await self.cs3.stop_loco(addr)
                logger.info("%s completed route — stopped.", self.train.name)
                break

            idx = next_idx

    async def _station_stop(self, block: Block):
        """Approach the station platform, stop, dwell, then prepare to depart."""
        addr = self.train.dcc_address
        logger.info("%s approaching station: %s", self.train.name, block.name)

        # Slow to approach speed
        await self.cs3.set_loco_speed(addr, APPROACH_SPEED, FORWARD)

        # Wait for s88 detection (train entered the block)
        if not USE_TIMED_BLOCKS:
            await self._wait_for_s88_occupied(block.s88_address)
        else:
            # Timed approach: estimate time to cross the block at approach speed
            await self._timed_traverse(block.length_mm, APPROACH_SPEED)

        # Stop
        await self.cs3.stop_loco(addr)
        dwell = self.layout.dwell_seconds(block.id)
        logger.info("%s stopped at %s — dwelling %ds", self.train.name, block.name, dwell)
        notify(self.train.name, f"Arrived at {block.name} — departing in {dwell}s")

        # Sound horn if the loco supports it (F2 is typical for Märklin MFX/DCC)
        await self.cs3.set_loco_function(addr, 2, True)
        await asyncio.sleep(1.0)
        await self.cs3.set_loco_function(addr, 2, False)

        # Wait dwell time
        await asyncio.sleep(dwell)

        logger.info("%s departing %s", self.train.name, block.name)

    async def _traverse_block(self, block: Block, next_block: Block):
        """Run through a non-station block at full speed."""
        addr = self.train.dcc_address
        speed = self.train.max_speed_step

        # If next block is a station, slow down earlier
        if next_block.is_station:
            speed = min(speed, APPROACH_SPEED + 20)

        await self.cs3.set_loco_speed(addr, speed, FORWARD)
        logger.debug("%s traversing %s at step %d", self.train.name, block.name, speed)

        if not USE_TIMED_BLOCKS:
            # Wait until the block's s88 sensor registers the train entering,
            # then wait until it clears (train has passed through)
            await self._wait_for_s88_occupied(block.s88_address)
            await self._wait_for_s88_clear(block.s88_address)
        else:
            await self._timed_traverse(block.length_mm, speed)

    async def _wait_for_block_clear(self, block: Block):
        """Pause until another train vacates the next block."""
        if block.occupied_by is not None:
            logger.info("%s waiting: block %s occupied by %s",
                        self.train.name, block.name, block.occupied_by)
            # Slow down while waiting (don't drive into an occupied block)
            await self.cs3.set_loco_speed(self.train.dcc_address, APPROACH_SPEED, FORWARD)
            while block.occupied_by is not None:
                await asyncio.sleep(0.5)
            logger.info("%s: block %s is now clear", self.train.name, block.name)

    async def _update_signal_for_block(self, block_id: str, occupied: bool):
        signal = self.layout.signal_for_block(block_id)
        if signal:
            if occupied:
                await self.cs3.set_signal_red(signal.dcc_address)
                logger.debug("Signal %s → RED (block %s occupied)", signal.name, block_id)
            else:
                await self.cs3.set_signal_green(signal.dcc_address)
                logger.debug("Signal %s → GREEN (block %s clear)", signal.name, block_id)

    # ── s88 sensor helpers ──────────────────────────────────────

    async def _wait_for_s88_occupied(self, s88_address: int):
        while self._running:
            if await self.cs3.get_s88_state(s88_address):
                return
            await asyncio.sleep(SENSOR_POLL_HZ)

    async def _wait_for_s88_clear(self, s88_address: int):
        while self._running:
            if not await self.cs3.get_s88_state(s88_address):
                return
            await asyncio.sleep(SENSOR_POLL_HZ)

    # ── Timed fallback (no sensors) ─────────────────────────────

    async def _timed_traverse(self, block_length_mm: int, speed_step: int):
        """
        Estimate traverse time from block length and speed step.
        HO scale 1:87.  Speed step 128 ≈ 130 km/h prototype = ~1.5 m/s model.
        Linear approximation: model_speed_mm_per_s ≈ speed_step * 11.7
        """
        if speed_step == 0:
            return
        model_speed_mm_s = speed_step * 11.7  # very rough — tune per loco
        traverse_time = block_length_mm / model_speed_mm_s
        await asyncio.sleep(traverse_time)


class AutomationEngine:
    """Manages all TrainRunner instances and the global layout state."""

    def __init__(self, layout: Layout, cs3: CS3PlusClient):
        self.layout = layout
        self.cs3 = cs3
        self._runners: list[TrainRunner] = []

    async def start(self, route_id: str, train_ids: list[str]):
        route = self.layout.routes.get(route_id)
        if not route:
            raise ValueError(f"Unknown route: {route_id}")

        for tid in train_ids:
            train = self.layout.trains.get(tid)
            if not train:
                logger.warning("Unknown train id: %s — skipped", tid)
                continue
            runner = TrainRunner(
                train=train,
                route_block_ids=route.block_ids,
                layout=self.layout,
                cs3=self.cs3,
                loop_route=route.loop,
            )
            self._runners.append(runner)
            runner.start()

    async def stop_all(self):
        await self.cs3.emergency_stop_all()
        for runner in self._runners:
            await runner.stop()
        self._runners.clear()
        logger.info("All trains stopped.")
        notify("Emergency Stop", "All trains halted")
