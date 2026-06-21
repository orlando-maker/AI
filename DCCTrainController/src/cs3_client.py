"""
Märklin Central Station 3+ (CS3+) HTTP API client.

The CS3+ exposes a REST API on port 80 of its local network IP.
All loco speeds use DCC 128-step mode. Accessory commands follow
the DCC extended accessory decoder spec.
"""

import asyncio
import logging
from typing import Optional
import aiohttp

logger = logging.getLogger(__name__)

# CS3+ uses DCC direction: 1 = forward, 0 = reverse
FORWARD = 1
REVERSE = 0

# Accessory output positions
SIGNAL_RED = 0
SIGNAL_GREEN = 1


class CS3PlusClient:
    def __init__(self, ip: str, port: int = 80):
        self.base_url = f"http://{ip}:{port}"
        self._session: Optional[aiohttp.ClientSession] = None

    async def connect(self):
        timeout = aiohttp.ClientTimeout(total=5)
        self._session = aiohttp.ClientSession(timeout=timeout)
        # Verify connectivity
        try:
            async with self._session.get(f"{self.base_url}/api/loks") as resp:
                if resp.status == 200:
                    logger.info("Connected to CS3+ at %s", self.base_url)
                    return True
        except aiohttp.ClientError as e:
            logger.error("Cannot reach CS3+ at %s: %s", self.base_url, e)
            return False

    async def disconnect(self):
        if self._session:
            await self._session.close()
            self._session = None

    # ── Locomotive control ──────────────────────────────────────

    async def set_loco_speed(self, dcc_address: int, speed_step: int, direction: int = FORWARD):
        """Set loco speed. speed_step 0 = stop, 1–128 = speed, direction 1/0."""
        payload = {
            "speed": max(0, min(speed_step, 128)),
            "direction": direction,
        }
        await self._post(f"/api/loks/{dcc_address}/speed", payload)
        logger.debug("Loco %d → speed %d dir %d", dcc_address, speed_step, direction)

    async def stop_loco(self, dcc_address: int):
        """Bring loco to an immediate stop (speed 0)."""
        await self.set_loco_speed(dcc_address, 0)

    async def emergency_stop_all(self):
        """Send CS3+ global emergency stop."""
        await self._post("/api/system/stop", {})
        logger.warning("EMERGENCY STOP sent")

    async def resume_all(self):
        """Release emergency stop / go."""
        await self._post("/api/system/go", {})

    async def set_loco_function(self, dcc_address: int, function_num: int, state: bool):
        """Toggle a loco function (e.g. headlights = F0, horn = F2, etc.)"""
        payload = {"function": function_num, "state": int(state)}
        await self._post(f"/api/loks/{dcc_address}/functions", payload)

    async def get_loco_status(self, dcc_address: int) -> dict:
        """Return current speed/direction/functions dict for a loco."""
        return await self._get(f"/api/loks/{dcc_address}")

    async def discover_locos(self) -> list[dict]:
        """
        Return all locomotives the CS3+ knows about — MFX locos appear here
        automatically after they self-register on the track. DCC/MM locos appear
        after you add them manually in the CS3+ loco list.

        Each dict contains at minimum:
          id        – internal CS3+ loco ID (use this to control the loco)
          name      – name shown on CS3+ display
          address   – DCC/MM address (MFX locos use their MFX UID instead)
          protocol  – "mfx", "dcc", "mm2", etc.
          speed     – current speed step
          direction – current direction
          functions – list of function states
        """
        data = await self._get("/api/loks")
        if isinstance(data, list):
            return data
        # CS3+ sometimes wraps the list
        return data.get("loks", data.get("locomotives", []))

    async def get_loco_by_id(self, loco_id: str) -> dict:
        """Fetch a single loco's full status by its CS3+ internal ID."""
        return await self._get(f"/api/loks/{loco_id}")

    # ── Accessory / signal control ──────────────────────────────

    async def set_accessory(self, dcc_address: int, output: int, activate: bool):
        """
        Trigger a DCC accessory (turnout, signal, uncoupler…).
        output: 0 or 1 (straight/thrown, red/green, etc.)
        activate: True = energise coil / set state
        """
        payload = {"output": output, "activate": int(activate)}
        await self._post(f"/api/accessories/{dcc_address}", payload)
        logger.debug("Accessory %d output %d → %s", dcc_address, output, activate)

    async def set_signal_red(self, dcc_address: int):
        await self.set_accessory(dcc_address, SIGNAL_RED, True)

    async def set_signal_green(self, dcc_address: int):
        await self.set_accessory(dcc_address, SIGNAL_GREEN, True)

    # ── s88 feedback ────────────────────────────────────────────

    async def get_s88_state(self, s88_address: int) -> bool:
        """Return True if the s88 contact at address is occupied."""
        data = await self._get(f"/api/s88/{s88_address}")
        return bool(data.get("occupied", False))

    async def get_all_s88(self) -> dict:
        """Return full s88 feedback status dict."""
        return await self._get("/api/s88")

    # ── Internal helpers ─────────────────────────────────────────

    async def _get(self, path: str) -> dict:
        if not self._session:
            raise RuntimeError("Not connected to CS3+")
        try:
            async with self._session.get(f"{self.base_url}{path}") as resp:
                resp.raise_for_status()
                return await resp.json()
        except aiohttp.ClientError as e:
            logger.error("GET %s failed: %s", path, e)
            return {}

    async def _post(self, path: str, payload: dict) -> dict:
        if not self._session:
            raise RuntimeError("Not connected to CS3+")
        try:
            async with self._session.post(f"{self.base_url}{path}", json=payload) as resp:
                resp.raise_for_status()
                try:
                    return await resp.json()
                except Exception:
                    return {}
        except aiohttp.ClientError as e:
            logger.error("POST %s %s failed: %s", path, payload, e)
            return {}
