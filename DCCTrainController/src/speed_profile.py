"""
Smooth speed ramping for realistic acceleration and braking.

Instead of jumping instantly to a target speed, ramp gradually
over a configurable duration. Sends one command every TICK seconds.
"""

from __future__ import annotations
import asyncio
import logging
from .cs3_client import CS3PlusClient, FORWARD

logger = logging.getLogger(__name__)

TICK = 0.1  # seconds between speed updates during a ramp


async def ramp(
    cs3: CS3PlusClient,
    addr: int,
    from_step: int,
    to_step: int,
    duration_s: float,
    direction: int = FORWARD,
):
    """
    Smoothly transition from from_step to to_step over duration_s seconds.
    Sends ~10 speed commands per second for a fluid motion effect.
    """
    if from_step == to_step or duration_s <= 0:
        await cs3.set_loco_speed(addr, to_step, direction)
        return

    total_ticks = max(1, int(duration_s / TICK))
    delta_per_tick = (to_step - from_step) / total_ticks
    current = float(from_step)

    for _ in range(total_ticks - 1):
        current += delta_per_tick
        await cs3.set_loco_speed(addr, max(0, min(128, round(current))), direction)
        await asyncio.sleep(TICK)

    # Always land exactly on the target
    await cs3.set_loco_speed(addr, to_step, direction)
    logger.debug("Loco %d ramped %d → %d over %.1fs", addr, from_step, to_step, duration_s)


async def accelerate(cs3: CS3PlusClient, addr: int, to_step: int, direction: int = FORWARD):
    """Depart from rest — gentle ramp up over ~4 seconds."""
    await ramp(cs3, addr, 0, to_step, duration_s=4.0, direction=direction)


async def brake_to_approach(cs3: CS3PlusClient, addr: int, from_step: int, approach_step: int):
    """First stage of station stop — slow to approach speed over ~3 seconds."""
    await ramp(cs3, addr, from_step, approach_step, duration_s=3.0)


async def brake_to_stop(cs3: CS3PlusClient, addr: int, from_step: int):
    """Final stage of station stop — coast to zero over ~2.5 seconds."""
    await ramp(cs3, addr, from_step, 0, duration_s=2.5)
