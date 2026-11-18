"""Bounded UDP link emulator for real LAN/ENet device acceptance tests.

This forwards raw UDP datagrams; it does not replace, decode, or acknowledge
ENet. Every downstream client gets a separate connected upstream socket, so
the real host sees separate peers. No OS network settings are changed.

Example:
  python tools/lan_impairment_proxy.py --listen 0.0.0.0:23122 \
    --target 192.168.1.239:22122 --control output/link-profile.json \
    --stats output/link-stats.json --duration 180

Point test clients at the proxy's LAN address and port. Atomically replace the
control JSON to change the link without reconnecting. Example control JSON:
  {"name":"weak-wifi","seed":120,
   "upstream":{"latency_ms":60,"jitter_ms":35,"loss":0.03,
               "bytes_per_second":32000,"burst_every_ms":15000,
               "burst_duration_ms":600},
   "downstream":{"latency_ms":60,"jitter_ms":35,"loss":0.03,
                 "bytes_per_second":64000},
   "queue":{"max_packets":512,"max_bytes":262144,"max_delay_ms":2000}}

Latency and jitter are one-way; rates are UDP payload bytes/second, shared by
all clients in that direction, with at most one datagram of initial burst.
Zero rate means unlimited. Queue age includes
propagation delay. Loss is per datagram, so it also impairs ENet's ACKs and
retransmissions. Periodic outages first start at burst_every_ms after a profile
change and drop queued/new datagrams throughout the blackout. Changing a
profile keeps queued datagrams but resets link serialization
timing; queued packets retain their sampled propagation deadline. Old packets
still expire at the current queue-age limit. This emulates an impaired link,
not a particular Wi-Fi radio or an Internet service guarantee.
"""
from __future__ import annotations

import argparse
import dataclasses
import heapq
import json
import math
import os
from pathlib import Path
import random
import selectors
import socket
import threading
import time
from collections import deque
from typing import Any


MAX_DATAGRAM = 65507
HISTOGRAM_MS = (1, 5, 10, 20, 40, 80, 160, 320, 640, 1000, 2000, 5000, 10000, 30000)


def number(value: Any, key: str, low: float, high: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{key} must be a number")
    if not math.isfinite(value) or not low <= value <= high:
        raise ValueError(f"{key} must be between {low} and {high}")
    return float(value)


def integer(value: Any, key: str, low: int, high: int) -> int:
    result = number(value, key, low, high)
    if result != math.floor(result):
        raise ValueError(f"{key} must be an integer")
    return int(result)


def fields(value: Any, allowed: set[str], label: str) -> dict:
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    unknown = value.keys() - allowed
    if unknown:
        raise ValueError(f"Unknown {label} fields: {', '.join(sorted(unknown))}")
    return value


@dataclasses.dataclass(frozen=True)
class Link:
    latency_ms: float = 0
    jitter_ms: float = 0
    loss: float = 0
    bytes_per_second: float = 0
    burst_every_ms: float = 0
    burst_duration_ms: float = 0

    @classmethod
    def parse(cls, value: Any) -> Link:
        value = fields(value, {f.name for f in dataclasses.fields(cls)}, "link")
        result = cls(
            latency_ms=number(value.get("latency_ms", 0), "latency_ms", 0, 10000),
            jitter_ms=number(value.get("jitter_ms", 0), "jitter_ms", 0, 10000),
            loss=number(value.get("loss", 0), "loss", 0, 1),
            bytes_per_second=number(value.get("bytes_per_second", 0), "bytes_per_second", 0, 1e9),
            burst_every_ms=number(value.get("burst_every_ms", 0), "burst_every_ms", 0, 3600000),
            burst_duration_ms=number(value.get("burst_duration_ms", 0), "burst_duration_ms", 0, 60000),
        )
        if result.burst_duration_ms > result.burst_every_ms:
            raise ValueError("burst_duration_ms cannot exceed burst_every_ms")
        return result


@dataclasses.dataclass(frozen=True)
class QueueLimits:
    max_packets: int = 512
    max_bytes: int = 262144
    max_delay_ms: float = 2000

    @classmethod
    def parse(cls, value: Any) -> QueueLimits:
        value = fields(value, {f.name for f in dataclasses.fields(cls)}, "queue")
        return cls(
            max_packets=integer(value.get("max_packets", 512), "max_packets", 1, 8192),
            max_bytes=integer(value.get("max_bytes", 262144), "max_bytes", 1, 8 * 1024 * 1024),
            max_delay_ms=number(value.get("max_delay_ms", 2000), "max_delay_ms", 1, 30000),
        )


@dataclasses.dataclass(frozen=True)
class Profile:
    name: str = "clean"
    seed: int = 120
    upstream: Link = dataclasses.field(default_factory=Link)
    downstream: Link = dataclasses.field(default_factory=Link)
    queue: QueueLimits = dataclasses.field(default_factory=QueueLimits)

    @classmethod
    def parse(cls, value: Any) -> Profile:
        value = fields(value, {f.name for f in dataclasses.fields(cls)}, "profile")
        name = value.get("name", "custom")
        if not isinstance(name, str) or not 1 <= len(name) <= 80 or any(ord(c) < 32 for c in name):
            raise ValueError("name must be 1–80 printable characters")
        return cls(name, integer(value.get("seed", 120), "seed", 0, 2**32 - 1),
                   Link.parse(value.get("upstream", {})), Link.parse(value.get("downstream", {})),
                   QueueLimits.parse(value.get("queue", {})))


@dataclasses.dataclass
class Client:
    address: tuple[str, int]
    upstream: socket.socket
    last_seen: float
    closed: bool = False
    received_upstream_bytes: int = 0
    received_downstream_bytes: int = 0


@dataclasses.dataclass(order=True)
class Packet:
    ready_at: float
    serial: int
    queued_at: float = dataclasses.field(compare=False)
    client: Client = dataclasses.field(compare=False)
    data: bytes = dataclasses.field(compare=False)


class Direction:
    def __init__(self, name: str, profile: Profile, now: float):
        self.name = name
        self.queue: list[Packet] = []
        self.queue_bytes = 0
        self.next_send = now
        self.serial = 0
        self.counts = {key: 0 for key in (
            "received_packets", "received_bytes", "forwarded_packets", "forwarded_bytes",
            "dropped_loss", "dropped_outage", "dropped_queue_full", "dropped_expired",
            "dropped_socket", "dropped_closed_client", "dropped_shutdown", "dropped_bytes",
            "max_queue_packets", "max_queue_bytes")}
        self.max_residence_ms = 0.0
        self.total_residence_ms = 0.0
        self.histogram = [0] * (len(HISTOGRAM_MS) + 1)
        self.configure(profile, now)

    def configure(self, profile: Profile, now: float) -> None:
        self.link = getattr(profile, self.name)
        self.limits = profile.queue
        self.profile_started = now
        self.random = random.Random(profile.seed + (0 if self.name == "upstream" else 1000003))
        self.next_send = now
        # A live profile may lower the caps. Enforce them immediately.
        while self.queue and (len(self.queue) > self.limits.max_packets or self.queue_bytes > self.limits.max_bytes):
            self.drop(self.pop(), "queue_full")

    def drop(self, packet: Packet, reason: str) -> None:
        self.counts["dropped_" + reason] += 1
        self.counts["dropped_bytes"] += len(packet.data)

    def pop(self) -> Packet:
        packet = heapq.heappop(self.queue)
        self.queue_bytes -= len(packet.data)
        return packet

    def in_outage(self, now: float) -> bool:
        elapsed = (now - self.profile_started) * 1000
        return bool(self.link.burst_every_ms and elapsed >= self.link.burst_every_ms
                    and elapsed % self.link.burst_every_ms < self.link.burst_duration_ms)

    def receive(self, data: bytes, client: Client, now: float) -> None:
        self.counts["received_packets"] += 1
        self.counts["received_bytes"] += len(data)
        self.serial += 1
        packet = Packet(now, self.serial, now, client, data)
        if self.in_outage(now):
            self.drop(packet, "outage")
            return
        if self.link.loss and self.random.random() < self.link.loss:
            self.drop(packet, "loss")
            return
        if len(self.queue) >= self.limits.max_packets or self.queue_bytes + len(data) > self.limits.max_bytes:
            self.drop(packet, "queue_full")
            return
        delay = self.link.latency_ms
        if self.link.jitter_ms:
            delay += self.random.uniform(-self.link.jitter_ms, self.link.jitter_ms)
        packet.ready_at = now + max(0.0, delay) / 1000
        heapq.heappush(self.queue, packet)
        self.queue_bytes += len(data)
        self.counts["max_queue_packets"] = max(self.counts["max_queue_packets"], len(self.queue))
        self.counts["max_queue_bytes"] = max(self.counts["max_queue_bytes"], self.queue_bytes)

    def pump(self, now: float, listener: socket.socket) -> None:
        if self.in_outage(now):
            # A blackout affects queued traffic as well as new arrivals. Letting
            # a bandwidth backlog drain here would falsely look like recovery.
            while self.queue:
                self.drop(self.pop(), "outage")
            return
        # Bounded scan also expires a long-propagation packet behind newer ones.
        live = []
        for packet in self.queue:
            if packet.client.closed:
                self.drop(packet, "closed_client")
            elif (now - packet.queued_at) * 1000 > self.limits.max_delay_ms:
                self.drop(packet, "expired")
            else:
                live.append(packet)
        if len(live) != len(self.queue):
            self.queue = live
            heapq.heapify(self.queue)
            self.queue_bytes = sum(len(p.data) for p in self.queue)
        attempts = 0
        while self.queue and self.queue[0].ready_at <= now and self.next_send <= now and attempts < 128:
            packet = self.pop()
            attempts += 1
            try:
                if self.name == "upstream":
                    size = packet.client.upstream.send(packet.data)
                else:
                    size = listener.sendto(packet.data, packet.client.address)
                if size != len(packet.data):
                    raise OSError("partial UDP send")
            except OSError:
                self.drop(packet, "socket")
                continue
            self.counts["forwarded_packets"] += 1
            self.counts["forwarded_bytes"] += len(packet.data)
            residence = (now - packet.queued_at) * 1000
            self.max_residence_ms = max(self.max_residence_ms, residence)
            self.total_residence_ms += residence
            bucket = next((i for i, bound in enumerate(HISTOGRAM_MS) if residence <= bound), len(HISTOGRAM_MS))
            self.histogram[bucket] += 1
            if self.link.bytes_per_second:
                # Preserve serialization time already earned while this queue
                # was backlogged. Restarting at `now` loses every scheduler
                # oversleep (notably Windows' coarse select timeout), turning a
                # 16 KiB/s link into roughly 9 KiB/s. A packet cannot earn credit
                # before its propagation deadline, so idle time never creates
                # an unbounded burst. Catch-up work remains capped per pump.
                self.next_send = max(self.next_send, packet.ready_at) + len(packet.data) / self.link.bytes_per_second

    def report(self, now: float) -> dict:
        return {**self.counts, "queue_packets": len(self.queue), "queue_bytes": self.queue_bytes,
                "oldest_queue_ms": max(((now - p.queued_at) * 1000 for p in self.queue), default=0),
                "mean_residence_ms": self.total_residence_ms / max(1, self.counts["forwarded_packets"]),
                "max_residence_ms": self.max_residence_ms,
                "residence_histogram_upper_ms": [*HISTOGRAM_MS, "overflow"],
                "residence_histogram_counts": list(self.histogram)}


class Proxy:
    def __init__(self, listen: tuple[str, int], target: tuple[str, int], profile: Profile | None = None,
                 control: Path | None = None, stats: Path | None = None, max_clients: int = 8,
                 idle_seconds: float = 120):
        self.max_clients = integer(max_clients, "max_clients", 1, 64)
        self.idle_seconds = number(idle_seconds, "idle_seconds", 1, 3600)
        self.started = time.monotonic()
        self.target = target
        self.control, self.stats = control, stats
        self.profile = profile or Profile()
        self.profile_events: deque[dict] = deque(maxlen=32)
        self.last_control_signature = None
        self.control_errors = 0
        self.last_control_error = None
        self.stats_write_errors = 0
        self.clients_created = 0
        self.clients_rejected = 0
        self.clients_expired = 0
        self.clients: dict[tuple[str, int], Client] = {}
        self.selector = selectors.DefaultSelector()
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.listener.bind(listen)
        self.listener.setblocking(False)
        self.address = self.listener.getsockname()
        self.selector.register(self.listener, selectors.EVENT_READ, None)
        self.directions = {name: Direction(name, self.profile, self.started) for name in ("upstream", "downstream")}
        self.stop_event = threading.Event()
        self.closed = False
        self.timer_resolution_ms = None
        self.timer_resolution_active = False
        self._timer_api = None
        self.configure(self.profile, self.started)

    def start_timer_resolution(self) -> None:
        # The virtual serializer preserves throughput even with coarse waits.
        # A short-lived Windows timer request also avoids bunching the packets
        # into coarse wakeups. Pair every successful request with timeEndPeriod.
        if os.name != "nt" or self.timer_resolution_active:
            return
        try:
            import ctypes
            api = ctypes.WinDLL("winmm")
            api.timeBeginPeriod.argtypes = [ctypes.c_uint]
            api.timeBeginPeriod.restype = ctypes.c_uint
            api.timeEndPeriod.argtypes = [ctypes.c_uint]
            api.timeEndPeriod.restype = ctypes.c_uint
            if api.timeBeginPeriod(1) == 0:
                self._timer_api = api
                self.timer_resolution_ms = 1
                self.timer_resolution_active = True
        except (OSError, AttributeError):
            pass  # Serialization accounting still works without this API.

    def configure(self, profile: Profile, now: float) -> None:
        self.profile = profile
        for direction in self.directions.values():
            direction.configure(profile, now)
        self.profile_events.append({"elapsed_seconds": now - self.started, "profile": dataclasses.asdict(profile)})

    def reload_control(self, now: float) -> None:
        if self.control is None:
            return
        try:
            stat = self.control.stat()
            signature = (stat.st_mtime_ns, stat.st_size)
            if signature == self.last_control_signature:
                return
            self.last_control_signature = signature
            if stat.st_size > 65536:
                raise ValueError("Profile file exceeds 64 KiB")
            profile = Profile.parse(json.loads(self.control.read_text(encoding="utf-8-sig")))
            self.configure(profile, now)
            self.last_control_error = None
        except (OSError, ValueError) as error:
            message = str(error)[:256]
            if message != self.last_control_error:
                self.control_errors += 1
            self.last_control_error = message

    def new_client(self, address: tuple[str, int], now: float) -> Client | None:
        if len(self.clients) >= self.max_clients:
            self.clients_rejected += 1
            return None
        upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            upstream.connect(self.target)
            upstream.setblocking(False)
            client = Client(address, upstream, now)
            self.selector.register(upstream, selectors.EVENT_READ, client)
        except OSError:
            upstream.close()
            self.clients_rejected += 1
            return None
        self.clients[address] = client
        self.clients_created += 1
        return client

    def expire_clients(self, now: float) -> None:
        for address, client in list(self.clients.items()):
            if now - client.last_seen <= self.idle_seconds:
                continue
            client.closed = True
            self.selector.unregister(client.upstream)
            client.upstream.close()
            del self.clients[address]
            self.clients_expired += 1

    def receive(self, key: selectors.SelectorKey, now: float) -> None:
        for _ in range(64):
            try:
                if key.data is None:
                    data, address = self.listener.recvfrom(MAX_DATAGRAM + 1)
                    client = self.clients.get(address) or self.new_client(address, now)
                    direction = self.directions["upstream"]
                    if client is None:
                        continue
                    client.received_upstream_bytes += len(data)
                else:
                    client = key.data
                    data = client.upstream.recv(MAX_DATAGRAM + 1)
                    direction = self.directions["downstream"]
                    client.received_downstream_bytes += len(data)
                client.last_seen = now
                direction.receive(data, client, now)
            except BlockingIOError:
                break
            except (ConnectionResetError, ConnectionRefusedError):
                break  # UDP ICMP error; keep the other peers and the proxy alive.

    def report(self) -> dict:
        now = time.monotonic()
        return {"measurement": "Raw UDP link impairment; ENet remains end-to-end", "running": not self.closed,
                "listen": list(self.address), "target": list(self.target), "elapsed_seconds": now - self.started,
                "profile": dataclasses.asdict(self.profile), "profile_history": list(self.profile_events),
                "control_errors": self.control_errors, "last_control_error": self.last_control_error,
                "stats_write_errors": self.stats_write_errors,
                "rate_scheduler": "virtual_serialization",
                "timer_resolution_ms": self.timer_resolution_ms,
                "timer_resolution_active": self.timer_resolution_active,
                "clients_created": self.clients_created, "clients_rejected": self.clients_rejected,
                "clients_expired": self.clients_expired, "active_clients": len(self.clients),
                "clients": [{"address": list(c.address), "upstream_local_address": list(c.upstream.getsockname()),
                             "received_upstream_bytes": c.received_upstream_bytes,
                             "received_downstream_bytes": c.received_downstream_bytes} for c in self.clients.values()],
                "directions": {name: d.report(now) for name, d in self.directions.items()}}

    def write_stats(self) -> None:
        if self.stats is None:
            return
        self.stats.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.stats.with_name(self.stats.name + ".tmp")
        temporary.write_text(json.dumps(self.report(), indent=2) + "\n", encoding="utf-8")
        try:
            os.replace(temporary, self.stats)
        except PermissionError:
            # A Windows observer can briefly hold the previous stats file open.
            # Retain it and retry next reporting tick without interrupting UDP.
            self.stats_write_errors += 1

    def serve(self, duration: float | None = None) -> None:
        self.start_timer_resolution()
        deadline = self.started + duration if duration is not None else math.inf
        next_control = next_stats = next_expiry = self.started
        try:
            while not self.stop_event.is_set():
                now = time.monotonic()
                if now >= deadline:
                    break
                if now >= next_control:
                    self.reload_control(now)
                    next_control = now + .2
                if now >= next_expiry:
                    self.expire_clients(now)
                    next_expiry = now + 1
                for direction in self.directions.values():
                    direction.pump(now, self.listener)
                if now >= next_stats:
                    self.write_stats()
                    next_stats = now + 1
                due = min(next_control, next_stats, deadline, now + .025)
                for direction in self.directions.values():
                    if direction.queue:
                        due = min(due, max(direction.queue[0].ready_at, direction.next_send))
                for key, _ in self.selector.select(max(0, due - now)):
                    self.receive(key, time.monotonic())
        finally:
            self.close()

    def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        if self.timer_resolution_active:
            self._timer_api.timeEndPeriod(self.timer_resolution_ms)
            self.timer_resolution_active = False
            self._timer_api = None
        for direction in self.directions.values():
            while direction.queue:
                direction.drop(direction.pop(), "shutdown")
        for client in self.clients.values():
            client.closed = True
            self.selector.unregister(client.upstream)
            client.upstream.close()
        self.clients.clear()
        self.selector.unregister(self.listener)
        self.listener.close()
        self.selector.close()
        self.write_stats()


def endpoint(text: str) -> tuple[str, int]:
    host, separator, port = text.rpartition(":")
    if not separator:
        raise argparse.ArgumentTypeError("Use an IPv4 address and port, e.g. 127.0.0.1:22122")
    try:
        socket.inet_pton(socket.AF_INET, host)
        parsed = int(port)
        if not 0 <= parsed <= 65535:
            raise ValueError()
    except (OSError, ValueError):
        raise argparse.ArgumentTypeError("Use a valid IPv4 address and UDP port") from None
    return host, parsed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--listen", type=endpoint, default=("0.0.0.0", 23122))
    parser.add_argument("--target", type=endpoint, required=True)
    parser.add_argument("--control", type=Path, required=True)
    parser.add_argument("--stats", type=Path, required=True)
    parser.add_argument("--duration", type=float)
    parser.add_argument("--max-clients", type=int, default=8)
    parser.add_argument("--idle-seconds", type=float, default=120)
    args = parser.parse_args()
    if args.duration is not None and (not math.isfinite(args.duration) or args.duration <= 0):
        parser.error("--duration must be positive and finite")
    if args.target[1] == 0:
        parser.error("The target port must be nonzero")
    # Fail initial configuration errors before opening a listener. Subsequent
    # partial/invalid writes retain the last valid profile and appear in stats.
    if args.control.stat().st_size > 65536:
        parser.error("Profile file exceeds 64 KiB")
    profile = Profile.parse(json.loads(args.control.read_text(encoding="utf-8-sig")))
    proxy = Proxy(args.listen, args.target, profile, args.control, args.stats, args.max_clients, args.idle_seconds)
    print(json.dumps({"ready": True, "listen": proxy.address, "target": args.target, "profile": profile.name}), flush=True)
    try:
        proxy.serve(args.duration)
    except KeyboardInterrupt:
        proxy.close()
    print(json.dumps(proxy.report()), flush=True)


if __name__ == "__main__":
    main()
