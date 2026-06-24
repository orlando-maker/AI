"""
Automation engine — drives trains around the layout like an autopilot.

Each autonomous train gets its own asyncio task. The task loops around
the route continuously, using smooth speed ramping for realistic motion.

Train types:
  stops_at_stations=True  — passenger train: decelerates, stops at platform,
                             waits dwell time, then departs smoothly
  stops_at_stations=False — cargo / express: slows to pass-through speed
                             at stations, then accelerates again — never stops

Two tracks run completely independently. If a train is set autonomous=False,
the software leaves it alone — the user drives it from the CS3+ handset.

Auto-start: when a train's starting block s88 sensor fires (loco placed on
track), the runner begins automatically (requires s88 sensors).
"""

from __future__ import annotations
import asyncio
import logging
from typing import Optional

from .cs3_client import CS3PlusClient, FORWARD
from .layout import Layout, Block, TrainConfig
from .notify import notify
from . import speed_profile as sp

logger = logging.getLogger(__name__)

# Set True if you don't have s88 sensors wired yet.
# Engine estimates position by speed × time instead.
USE_TIMED_BLOCKS = False

SENSOR_POLL_HZ   = 0.25   # seconds between s88 polls
PASS_THROUGH_SPEED = 30   # speed step when a cargo train passes a station block


class TrainRunner:
    """Autopilot for a single train on a single route."""

    def __init__(
        self,
        train: TrainConfig,
        route_block_ids: list[str],
        layout: Layout,
        cs3: CS3PlusClient,
        loop_route: bool = True,
    ):
        self.train        = train
        self.route_block_ids = route_block_ids
        self.layout       = layout
        self.cs3          = cs3
        self.loop_route   = loop_route
        self._running     = False
        self._task: Optional[asyncio.Task] = None
        self.current_block_name = "—"
        self.status = "idle"

    def start(self):
        self._running = True
        self._task = asyncio.create_task(
            self._run(), name=f"runner_{self.train.id}"
        )
        logger.info("Autopilot started: %s (addr %d)", self.train.name, self.train.dcc_address)

    async def stop(self):
        self._running = False
        self.status = "stopped"
        await self.cs3.stop_loco(self.train.dcc_address)
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    # ── Main loop ────────────────────────────────────────────────

    async def _run(self):
        addr = self.train.dcc_address

        # Headlights on (F0)
        await self.cs3.set_loco_function(addr, 0, True)

        idx = 0
        current_speed = 0

        while self._running:
            block_ids  = self.route_block_ids
            cur_id     = block_ids[idx % len(block_ids)]
            next_idx   = (idx + 1) % len(block_ids)
            next_id    = block_ids[next_idx]

            cur_block  = self.layout.blocks.get(cur_id)
            next_block = self.layout.blocks.get(next_id)

            if not cur_block or not next_block:
                logger.error("Unknown block: %s or %s", cur_id, next_id)
                break

            # Mark block occupied
            cur_block.occupied_by = self.train.id
            self.current_block_name = cur_block.name
            await self._set_signal(cur_id, red=True)

            if cur_block.is_station and self.train.stops_at_stations:
                current_speed = await self._station_stop(cur_block, current_speed)
            elif cur_block.is_station and not self.train.stops_at_stations:
                current_speed = await self._pass_through_station(cur_block, current_speed)
            else:
                current_speed = await self._run_block(cur_block, next_block, current_speed)

            # Wait for next block to be free
            await self._wait_for_block_clear(next_block)
            await self._set_signal(next_id, red=False)

            # Release current block
            cur_block.occupied_by = None
            await self._set_signal(cur_id, red=False)

            if not self.loop_route and next_idx == 0:
                await self.cs3.stop_loco(addr)
                self.status = "finished"
                logger.info("%s completed route.", self.train.name)
                return

            idx = next_idx

    # ── Block handlers ───────────────────────────────────────────

    async def _run_block(self, block: Block, next_block: Block, current_speed: int) -> int:
        """Cruise through a non-station block. Pre-slow if next block is a station."""
        addr   = self.train.dcc_address
        target = self.train.max_speed_step

        # If next block is a station, start easing off before we get there
        if next_block.is_station and self.train.stops_at_stations:
            target = self.train.approach_speed_step + 15

        self.status = f"running → {block.name}"
        if current_speed != target:
            await sp.ramp(self.cs3, addr, current_speed, target, duration_s=3.0)

        await self._await_block_traversal(block, target)
        return target

    async def _station_stop(self, block: Block, current_speed: int) -> int:
        """Full station stop: brake → stop → dwell → depart."""
        addr  = self.train.dcc_address
        approach = self.train.approach_speed_step

        self.status = f"braking → {block.name}"
        logger.info("%s braking for station: %s", self.train.name, block.name)

        # Stage 1: slow to approach speed
        await sp.brake_to_approach(self.cs3, addr, current_speed, approach)

        # Wait for s88 to confirm train is in the station block
        if not USE_TIMED_BLOCKS:
            await self._wait_s88_occupied(block.s88_address)

        # Stage 2: glide to a stop
        self.status = f"stopping at {block.name}"
        await sp.brake_to_stop(self.cs3, addr, approach)

        dwell = self.layout.dwell_seconds(block.id)
        logger.info("%s at %s — dwell %ds", self.train.name, block.name, dwell)
        notify(self.train.name, f"Arrived at {block.name} — departing in {dwell}s")

        # Horn
        await self.cs3.set_loco_function(addr, 2, True)
        await asyncio.sleep(1.0)
        await self.cs3.set_loco_function(addr, 2, False)

        self.status = f"at station: {block.name}"
        await asyncio.sleep(dwell)

        # Depart smoothly
        self.status = f"departing {block.name}"
        logger.info("%s departing %s", self.train.name, block.name)
        target = self.train.max_speed_step
        await sp.accelerate(self.cs3, addr, target)
        return target

    async def _pass_through_station(self, block: Block, current_speed: int) -> int:
        """Cargo/express: slow slightly through the station, then speed back up."""
        addr = self.train.dcc_address
        self.status = f"passing {block.name} (no stop)"
        logger.info("%s passing through %s without stopping", self.train.name, block.name)

        await sp.ramp(self.cs3, addr, current_speed, PASS_THROUGH_SPEED, duration_s=2.5)
        await self._await_block_traversal(block, PASS_THROUGH_SPEED)
        target = self.train.max_speed_step
        await sp.ramp(self.cs3, addr, PASS_THROUGH_SPEED, target, duration_s=3.0)
        return target

    # ── Block traversal ──────────────────────────────────────────

    async def _await_block_traversal(self, block: Block, speed_step: int):
        """Wait until the train has passed through a block."""
        if USE_TIMED_BLOCKS:
            await self._timed_traverse(block.length_mm, speed_step)
        else:
            await self._wait_s88_occupied(block.s88_address)
            await self._wait_s88_clear(block.s88_address)

    async def _wait_for_block_clear(self, block: Block):
        if block.occupied_by is not None and block.occupied_by != self.train.id:
            logger.info("%s holding: %s is occupied by %s",
                        self.train.name, block.name, block.occupied_by)
            self.status = f"waiting — {block.name} occupied"
            # Slow to a crawl while waiting, don't run into another train
            await self.cs3.set_loco_speed(
                self.train.dcc_address, self.train.approach_speed_step
            )
            while block.occupied_by is not None and block.occupied_by != self.train.id:
                await asyncio.sleep(0.5)
            logger.info("%s: %s is clear — proceeding", self.train.name, block.name)

    # ── Signal helpers ───────────────────────────────────────────

    async def _set_signal(self, block_id: str, red: bool):
        sig = self.layout.signal_for_block(block_id)
        if sig:
            if red:
                await self.cs3.set_signal_red(sig.dcc_address)
            else:
                await self.cs3.set_signal_green(sig.dcc_address)

    # ── s88 helpers ──────────────────────────────────────────────

    async def _wait_s88_occupied(self, s88_address: int):
        while self._running:
            if await self.cs3.get_s88_state(s88_address):
                return
            await asyncio.sleep(SENSOR_POLL_HZ)

    async def _wait_s88_clear(self, s88_address: int):
        while self._running:
            if not await self.cs3.get_s88_state(s88_address):
                return
            await asyncio.sleep(SENSOR_POLL_HZ)

    # ── Timed fallback ───────────────────────────────────────────

    async def _timed_traverse(self, block_length_mm: int, speed_step: int):
        """
        HO 1:87. Speed step 128 ≈ 130 km/h prototype ≈ 1495 mm/s model.
        Linear approx: model_mm_per_s ≈ speed_step * 11.7
        """
        if speed_step == 0:
            return
        model_speed = speed_step * 11.7
        await asyncio.sleep(block_length_mm / model_speed)


# ── Auto-start watcher ────────────────────────────────────────────────────────

class TrackWatcher:
    """
    Watches the first block of a track for an s88 trigger.
    When a loco is placed on the track and the sensor fires,
    automatically starts the assigned train's autopilot.
    """

    def __init__(self, track_id: str, layout: Layout, cs3: CS3PlusClient,
                 engine: "AutomationEngine"):
        self.track_id = track_id
        self.layout   = layout
        self.cs3      = cs3
        self.engine   = engine
        self._task: Optional[asyncio.Task] = None

    def start(self):
        self._task = asyncio.create_task(
            self._watch(), name=f"watcher_{self.track_id}"
        )

    async def _watch(self):
        route = self.layout.route_for_track(self.track_id)
        if not route or not route.block_ids:
            return
        first_block = self.layout.blocks.get(route.block_ids[0])
        if not first_block or USE_TIMED_BLOCKS:
            return

        logger.info("Watching %s s88:%d for auto-start…",
                    self.track_id, first_block.s88_address)
        while True:
            occupied = await self.cs3.get_s88_state(first_block.s88_address)
            if occupied and not self.engine.track_is_running(self.track_id):
                logger.info("Loco detected on %s — starting autopilot", self.track_id)
                notify("Auto-start", f"Loco detected on {self.track_id} — autopilot engaged")
                await self.engine.start_track(self.track_id)
            await asyncio.sleep(1.0)


# ── Engine ────────────────────────────────────────────────────────────────────

class AutomationEngine:
    """Manages all TrainRunner tasks and track watchers."""

    def __init__(self, layout: Layout, cs3: CS3PlusClient):
        self.layout   = layout
        self.cs3      = cs3
        self._runners: dict[str, TrainRunner] = {}   # train_id → runner
        self._watchers: list[TrackWatcher]    = []

    def track_is_running(self, track_id: str) -> bool:
        return any(
            r._running and r.train.track == track_id
            for r in self._runners.values()
        )

    def start_watchers(self):
        """Begin watching all tracks for auto-start triggers."""
        tracks = {t.track for t in self.layout.trains.values() if t.autonomous}
        for track_id in tracks:
            w = TrackWatcher(track_id, self.layout, self.cs3, self)
            w.start()
            self._watchers.append(w)

    async def start_track(self, track_id: str):
        """Start autopilot for all autonomous trains on a given track."""
        route = self.layout.route_for_track(track_id)
        if not route:
            logger.warning("No route defined for %s", track_id)
            return
        trains = [t for t in self.layout.trains.values()
                  if t.autonomous and t.track == track_id]
        for train in trains:
            if train.id not in self._runners or not self._runners[train.id]._running:
                runner = TrainRunner(
                    train=train,
                    route_block_ids=route.block_ids,
                    layout=self.layout,
                    cs3=self.cs3,
                    loop_route=route.loop,
                )
                self._runners[train.id] = runner
                runner.start()

    async def start_all(self):
        """Start autopilot on every track that has autonomous trains."""
        tracks = {t.track for t in self.layout.trains.values() if t.autonomous}
        for track_id in tracks:
            await self.start_track(track_id)

    async def stop_all(self):
        await self.cs3.emergency_stop_all()
        for runner in self._runners.values():
            await runner.stop()
        self._runners.clear()
        logger.info("All trains stopped.")
        notify("Emergency Stop", "All trains halted")

    def status_lines(self) -> list[str]:
        """Return a list of status strings for the live display."""
        lines = []
        for runner in self._runners.values():
            t = runner.train
            kind = "PASS" if t.stops_at_stations else "CARGO"
            lines.append(
                f"  [{t.track}] {t.name:<22} {kind:<6}  {runner.status}"
            )
        if not lines:
            lines.append("  No autonomous trains running.")
        return lines
