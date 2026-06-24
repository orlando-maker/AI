"""
Layout model — loads layout.yaml and represents blocks, stations, signals, routes.
"""

from __future__ import annotations
import yaml
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class TrainConfig:
    id: str
    name: str
    protocol: str           # mfx | dcc | mm2
    dcc_address: int
    length_mm: int
    max_speed_step: int
    approach_speed_step: int   # speed used when entering a station block
    decel_distance_mm: int
    autonomous: bool           # True = software drives it; False = you drive it manually
    stops_at_stations: bool    # False = cargo/express — passes through without stopping
    track: str                 # which track this train runs on (e.g. "track_1")


@dataclass
class Block:
    id: str
    name: str
    length_mm: int
    is_station: bool
    platform_length_mm: Optional[int]
    s88_address: int
    track: str                 # which track this block belongs to
    # Runtime state (set by automation engine)
    occupied_by: Optional[str] = None   # train id or None
    train_status: str = "—"            # human-readable status string for display


@dataclass
class Signal:
    id: str
    name: str
    dcc_address: int
    protects_block: str


@dataclass
class Route:
    id: str
    name: str
    block_ids: list[str]
    loop: bool
    track: str


@dataclass
class Layout:
    trains: dict[str, TrainConfig]
    blocks: dict[str, Block]
    signals: dict[str, Signal]
    routes: dict[str, Route]
    station_dwell: dict[str, int]
    cs3_ip: str
    cs3_port: int

    def station_blocks(self) -> list[Block]:
        return [b for b in self.blocks.values() if b.is_station]

    def signal_for_block(self, block_id: str) -> Optional[Signal]:
        for sig in self.signals.values():
            if sig.protects_block == block_id:
                return sig
        return None

    def dwell_seconds(self, block_id: str) -> int:
        return self.station_dwell.get(block_id, self.station_dwell.get("default", 15))

    def autonomous_trains(self) -> list[TrainConfig]:
        return [t for t in self.trains.values() if t.autonomous]

    def route_for_track(self, track_id: str) -> Optional[Route]:
        for r in self.routes.values():
            if r.track == track_id:
                return r
        return None

    def blocks_for_track(self, track_id: str) -> list[Block]:
        return [b for b in self.blocks.values() if b.track == track_id]


def load_layout(config_path: str) -> Layout:
    with open(config_path) as f:
        raw = yaml.safe_load(f)

    trains = {
        t["id"]: TrainConfig(
            id=t["id"],
            name=t["name"],
            protocol=t.get("protocol", "mfx"),
            dcc_address=t["dcc_address"],
            length_mm=t["length_mm"],
            max_speed_step=t["max_speed_step"],
            approach_speed_step=t.get("approach_speed_step", 20),
            decel_distance_mm=t["decel_distance_mm"],
            autonomous=t.get("autonomous", True),
            stops_at_stations=t.get("stops_at_stations", True),
            track=t.get("track", "track_1"),
        )
        for t in raw.get("trains", [])
    }

    blocks = {
        b["id"]: Block(
            id=b["id"],
            name=b["name"],
            length_mm=b["length_mm"],
            is_station=b.get("is_station", False),
            platform_length_mm=b.get("platform_length_mm"),
            s88_address=b["s88_address"],
            track=b.get("track", "track_1"),
        )
        for b in raw.get("blocks", [])
    }

    signals = {
        s["id"]: Signal(
            id=s["id"],
            name=s["name"],
            dcc_address=s["dcc_address"],
            protects_block=s["protects_block"],
        )
        for s in raw.get("signals", [])
    }

    routes = {
        r["id"]: Route(
            id=r["id"],
            name=r["name"],
            block_ids=r["blocks"],
            loop=r.get("loop", False),
            track=r.get("track", "track_1"),
        )
        for r in raw.get("routes", [])
    }

    dwell_raw = raw.get("station_dwell", {})
    dwell: dict[str, int] = {"default": int(dwell_raw.get("default_seconds", 15))}
    dwell.update({k: int(v) for k, v in dwell_raw.get("overrides", {}).items()})

    cs3 = raw.get("cs3_plus", {})
    return Layout(
        trains=trains,
        blocks=blocks,
        signals=signals,
        routes=routes,
        station_dwell=dwell,
        cs3_ip=cs3.get("ip", "192.168.1.100"),
        cs3_port=int(cs3.get("port", 80)),
    )
