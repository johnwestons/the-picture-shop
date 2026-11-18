from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import socket
import sys
import tempfile
import threading
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "lan_impairment_proxy.py"
SPEC = importlib.util.spec_from_file_location("lan_impairment_proxy", SCRIPT)
proxy_module = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = proxy_module
SPEC.loader.exec_module(proxy_module)


class Echo:
    def __init__(self):
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind(("127.0.0.1", 0))
        self.socket.settimeout(.03)
        self.address = self.socket.getsockname()
        self.received = []
        self.stopped = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        while not self.stopped.is_set():
            try:
                data, address = self.socket.recvfrom(65535)
                self.received.append((time.monotonic(), data, address))
                self.socket.sendto(data, address)
            except socket.timeout:
                pass

    def close(self):
        self.stopped.set()
        self.thread.join(1)
        self.socket.close()


class ImpairmentTests(unittest.TestCase):
    def setUp(self):
        self.echo = Echo()
        self.proxies = []
        self.clients = []
        self.directory = tempfile.TemporaryDirectory(prefix="tps-link-test-")

    def tearDown(self):
        for proxy, thread in self.proxies:
            proxy.stop_event.set()
            thread.join(2)
            self.assertFalse(thread.is_alive())
        for client in self.clients:
            client.close()
        self.echo.close()
        self.directory.cleanup()

    def start(self, profile, **options):
        proxy = proxy_module.Proxy(("127.0.0.1", 0), self.echo.address,
                                   proxy_module.Profile.parse(profile), **options)
        thread = threading.Thread(target=proxy.serve, daemon=True)
        thread.start()
        self.proxies.append((proxy, thread))
        return proxy

    def client(self, proxy):
        client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        client.bind(("127.0.0.1", 0))
        client.connect(proxy.address)
        client.settimeout(1)
        self.clients.append(client)
        return client

    def test_real_udp_delay_and_distinct_enet_peer_mapping(self):
        proxy = self.start({"upstream": {"latency_ms": 35}, "downstream": {"latency_ms": 45}})
        first, second = self.client(proxy), self.client(proxy)
        started = time.monotonic()
        first.send(b"first-client"); second.send(b"second-client")
        self.assertEqual(b"first-client", first.recv(100))
        self.assertGreaterEqual(time.monotonic() - started, .072)
        self.assertEqual(b"second-client", second.recv(100))
        self.assertEqual(2, len({row[2] for row in self.echo.received}))
        self.assertEqual(2, proxy.directions["downstream"].counts["forwarded_packets"])

    def test_bandwidth_limit_is_shared_between_clients_in_a_direction(self):
        proxy = self.start({"upstream": {"bytes_per_second": 1000}})
        clients = [self.client(proxy), self.client(proxy)]
        for i, client in enumerate(clients):
            client.send(bytes([i]) * 200)
        for i, client in enumerate(clients):
            self.assertEqual(bytes([i]) * 200, client.recv(300))
        self.assertGreaterEqual(self.echo.received[1][0] - self.echo.received[0][0], .18)
        self.assertEqual(400, proxy.directions["upstream"].counts["forwarded_bytes"])

    def test_seeded_loss_repeats_real_datagram_decisions(self):
        results = []
        for _ in range(2):
            proxy = self.start({"seed": 71, "upstream": {"loss": .4}})
            client = self.client(proxy)
            for i in range(40):
                client.send(bytes([i]))
            client.settimeout(.15)
            received = []
            while True:
                try:
                    received.append(client.recv(100)[0])
                except socket.timeout:
                    break
            self.assertGreater(len(received), 10)
            self.assertLess(len(received), 35)
            self.assertEqual(40 - len(received), proxy.directions["upstream"].counts["dropped_loss"])
            results.append(received)
        self.assertEqual(results[0], results[1])

    def test_jitter_reorders_real_datagrams_within_the_configured_window(self):
        proxy = self.start({"seed": 17, "upstream": {"latency_ms": 65, "jitter_ms": 50}})
        client = self.client(proxy)
        started = time.monotonic()
        for i in range(16):
            client.send(bytes([i]))
        received = [client.recv(100)[0] for _ in range(16)]
        self.assertEqual(list(range(16)), sorted(received))
        self.assertNotEqual(list(range(16)), received)
        self.assertGreaterEqual(self.echo.received[0][0] - started, .01)
        self.assertLess(self.echo.received[-1][0] - started, .4)

    def test_downstream_rate_does_not_throttle_upstream_delivery(self):
        proxy = self.start({"downstream": {"bytes_per_second": 1000}})
        client = self.client(proxy)
        client.send(b"a" * 200); client.send(b"b" * 200)
        self.assertEqual(b"a" * 200, client.recv(300))
        first_reply = time.monotonic()
        self.assertEqual(b"b" * 200, client.recv(300))
        self.assertGreaterEqual(time.monotonic() - first_reply, .18)
        self.assertLess(self.echo.received[1][0] - self.echo.received[0][0], .08)

    def test_queued_packets_are_bounded_and_expire_instead_of_replaying_late(self):
        proxy = self.start({"upstream": {"latency_ms": 500},
                            "queue": {"max_packets": 3, "max_bytes": 30, "max_delay_ms": 70}})
        client = self.client(proxy)
        for _ in range(20):
            client.send(b"0123456789")
        time.sleep(.15)
        direction = proxy.directions["upstream"]
        self.assertLessEqual(direction.counts["max_queue_packets"], 3)
        self.assertLessEqual(direction.counts["max_queue_bytes"], 30)
        self.assertEqual(17, direction.counts["dropped_queue_full"])
        self.assertEqual(3, direction.counts["dropped_expired"])
        self.assertEqual(0, direction.queue_bytes)
        self.assertEqual([], self.echo.received)

    def test_live_control_recovers_without_replacing_client_socket_and_rejects_bad_config(self):
        control = Path(self.directory.name) / "profile.json"
        stats = Path(self.directory.name) / "stats.json"
        control.write_text(json.dumps({"name": "blocked", "upstream": {"loss": 1}}))
        proxy = self.start({"upstream": {"loss": 1}}, control=control, stats=stats)
        client = self.client(proxy)
        client.send(b"lost")
        time.sleep(.04)
        self.assertEqual([], self.echo.received)
        identity = next(iter(proxy.clients.values())).upstream.getsockname()
        control.write_text(json.dumps({"name": "recovered"}))
        deadline = time.monotonic() + 1
        while proxy.profile.name != "recovered" and time.monotonic() < deadline:
            time.sleep(.01)
        client.send(b"recovered")
        self.assertEqual(b"recovered", client.recv(100))
        self.assertEqual(identity, next(iter(proxy.clients.values())).upstream.getsockname())
        control.write_text('{"upstream":{"loss":2}}')
        deadline = time.monotonic() + 1
        while proxy.control_errors == 0 and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertGreater(proxy.control_errors, 0)
        self.assertEqual("recovered", proxy.profile.name)
        client.send(b"still-valid")
        self.assertEqual(b"still-valid", client.recv(100))
        self.assertTrue(stats.exists())

    def test_periodic_burst_outage_then_recovery(self):
        proxy = self.start({"upstream": {"burst_every_ms": 150, "burst_duration_ms": 60}})
        client = self.client(proxy)
        client.send(b"before")
        self.assertEqual(b"before", client.recv(100))
        while time.monotonic() - proxy.started < .165:
            time.sleep(.002)
        client.send(b"during")
        time.sleep(.02)
        self.assertEqual(1, proxy.directions["upstream"].counts["dropped_outage"])
        while time.monotonic() - proxy.started < .225:
            time.sleep(.002)
        client.send(b"after")
        self.assertEqual(b"after", client.recv(100))

    def test_blackout_does_not_leak_packets_from_existing_latency_queue(self):
        proxy = self.start({"upstream": {"latency_ms": 200, "burst_every_ms": 150, "burst_duration_ms": 100}})
        client = self.client(proxy)
        client.send(b"queued-before-blackout")
        time.sleep(.28)
        self.assertEqual([], self.echo.received)
        self.assertEqual(1, proxy.directions["upstream"].counts["dropped_outage"])
        self.assertEqual(0, proxy.directions["upstream"].counts["forwarded_packets"])

    def test_client_count_is_bounded(self):
        proxy = self.start({}, max_clients=1)
        first = self.client(proxy)
        first.send(b"admitted")
        self.assertEqual(b"admitted", first.recv(100))
        second = self.client(proxy)
        second.send(b"not-admitted")
        time.sleep(.04)
        self.assertEqual(1, len(proxy.clients))
        self.assertEqual(1, proxy.clients_rejected)

    def test_configuration_rejects_unbounded_or_ambiguous_values(self):
        for value in ({"upstream": {"loss": float("nan")}}, {"queue": {"max_packets": 99999}},
                      {"seed": True}, {"upstream": {"latency": 10}},
                      {"downstream": {"burst_every_ms": 20, "burst_duration_ms": 30}}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                proxy_module.Profile.parse(value)

    def test_coarse_scheduler_preserves_rate_without_earning_idle_credit(self):
        class Sink:
            def send(self, data):
                return len(data)
        profile = proxy_module.Profile.parse({"upstream": {"bytes_per_second": 16000},
                                             "queue": {"max_delay_ms": 10000}})
        direction = proxy_module.Direction("upstream", profile, 0)
        client = proxy_module.Client(("127.0.0.1", 1), Sink(), 0)
        for _ in range(400):
            direction.receive(b"x" * 300, client, 0)
        for i in range(161):
            direction.pump(i / 32, None)
            self.assertLessEqual(direction.counts["forwarded_bytes"], i / 32 * 16000 + 300)
        self.assertGreaterEqual(direction.counts["forwarded_bytes"], 5 * 16000 * .99)
        while direction.queue:
            direction.pop()
        before = direction.counts["forwarded_packets"]
        for _ in range(10):
            direction.receive(b"x" * 300, client, 100)
        direction.pump(100, None)
        self.assertEqual(before + 1, direction.counts["forwarded_packets"])

    def test_windows_timer_request_is_released_on_close(self):
        proxy = self.start({})
        deadline = time.monotonic() + 1
        while not proxy.timer_resolution_active and time.monotonic() < deadline and proxy_module.os.name == "nt":
            time.sleep(.005)
        if proxy_module.os.name == "nt":
            self.assertTrue(proxy.timer_resolution_active)
            self.assertEqual(1, proxy.timer_resolution_ms)
        proxy.stop_event.set()
        self.proxies[-1][1].join(2)
        self.assertFalse(proxy.timer_resolution_active)

    def measure_saturated_rate(self, direction, packet_size, rate):
        proxy = self.start({direction: {"bytes_per_second": rate},
                            "queue": {"max_delay_ms": 10000}})
        client = self.client(proxy)
        client.settimeout(.05)
        stopped = threading.Event()
        replies = []
        def receive():
            while not stopped.is_set():
                try:
                    data = client.recv(65535)
                    replies.append((time.monotonic(), len(data)))
                except socket.timeout:
                    pass
        def send():
            payload = b"x" * packet_size
            batch = max(2, int(rate * .1 / packet_size))
            while not stopped.is_set():
                for _ in range(batch):
                    client.send(payload)
                stopped.wait(.05)
        threads = [threading.Thread(target=fn, daemon=True) for fn in (receive, send)]
        for thread in threads:
            thread.start()
        try:
            # Two overlapping five-second windows expose sustained scheduler
            # underdelivery, which two-packet minimum-delay tests cannot catch.
            stopped.wait(6)
        finally:
            stopped.set()
            for thread in threads:
                thread.join(2)
                self.assertFalse(thread.is_alive())
        received = [(row[0], len(row[1])) for row in self.echo.received] if direction == "upstream" else replies
        self.assertTrue(received)
        first = received[0][0]
        for offset in (0, .75):
            actual = sum(size for at, size in received if first + offset <= at < first + offset + 5)
            self.assertGreaterEqual(actual, .9 * rate * 5, (direction, actual / 5, rate))
            self.assertLessEqual(actual, rate * 5 + packet_size, (direction, actual / 5, rate))

    def test_saturated_small_udp_packets_deliver_configured_upstream_capacity(self):
        self.measure_saturated_rate("upstream", 300, 16000)

    def test_saturated_mtu_udp_packets_deliver_configured_downstream_capacity(self):
        self.measure_saturated_rate("downstream", 1300, 32000)


if __name__ == "__main__":
    unittest.main()
