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
    dcc_address: int
    length_mm: int
    max_speed_step: int
    decel_distance_mm: int


@dataclass
class Block:
    id: str
    name: str
    length_mm: int
    is_station: bool
    platform_length_mm: Optional[int]
    s88_address: int
    # Runtime state
    occupied_by: Optional[str] = None   # train id or None


@dataclass
class Signal:
    id: str
    name: str
    dcc_address: int
    protects_block: str   # block id


@dataclass
class Route:
    id: str
    name: str
    block_ids: list[str]
    loop: bool


@dataclass
class Layout:
    trains: dict[str, TrainConfig]
    blocks: dict[str, Block]
    signals: dict[str, Signal]
    routes: dict[str, Route]
    station_dwell: dict[str, int]   # block_id → seconds
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


def load_layout(config_path: str) -> Layout:
    with open(config_path) as f:
        raw = yaml.safe_load(f)

    trains = {
        t["id"]: TrainConfig(
            id=t["id"],
            name=t["name"],
            dcc_address=t["dcc_address"],
            length_mm=t["length_mm"],
            max_speed_step=t["max_speed_step"],
            decel_distance_mm=t["decel_distance_mm"],
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
