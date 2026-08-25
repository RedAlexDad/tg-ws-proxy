"""
Automatic failure recovery for the WS bridge.

Monitors upstream connection failures (WS connect, CF proxy, TCP fallback)
inside a rolling time window. When the error rate exceeds a threshold it
triggers:

  * SOFT reset  -- clear blacklists, cooldowns, pools and refresh the CF
                  domain list in place. Keeps the process running.
  * HARD reset  -- exit the process so the container is restarted by
                  Docker `--restart=always` / systemd. Only used when a
                  soft reset did not stop the error flood.

Both thresholds are reached through the error count accumulated by
`autorecover.record()`.
"""

import asyncio
import logging
import os
import time

from collections import deque
from typing import Awaitable, Callable, Optional

log = logging.getLogger('tg-mtproto-proxy')

ERROR_WINDOW = 60.0           # rolling window, seconds
SOFT_THRESHOLD = 60           # errors in window -> soft reset
HARD_THRESHOLD = 300          # errors in window -> hard reset (process exit)
HARD_AFTER_SOFT_SEC = 30.0    # min delay after a soft reset before hard reset
CHECK_INTERVAL = 10.0         # monitor tick, seconds

SoftResetCb = Callable[[], Awaitable[None]]
HardResetCb = Callable[[], None]


class AutoRecover:
    def __init__(self):
        self._errors: deque = deque()   # (monotonic_ts, kind)
        self._last_soft = 0.0
        self._last_hard = 0.0
        self.soft_resets = 0
        self.hard_resets = 0
        self._soft_cb: Optional[SoftResetCb] = None
        self._hard_cb: Optional[HardResetCb] = None

    # --- configuration -------------------------------------------------

    def configure(self, soft: SoftResetCb, hard: HardResetCb) -> None:
        self._soft_cb = soft
        self._hard_cb = hard

    # --- recording -----------------------------------------------------

    def record(self, kind: str = 'upstream') -> None:
        now = time.monotonic()
        self._errors.append((now, kind))
        self._prune(now)

    def count(self) -> int:
        self._prune(time.monotonic())
        return len(self._errors)

    def reset(self) -> None:
        self._errors.clear()
        self._last_soft = time.monotonic()

    def _prune(self, now: float) -> None:
        cutoff = now - ERROR_WINDOW
        while self._errors and self._errors[0][0] < cutoff:
            self._errors.popleft()

    # --- monitor -------------------------------------------------------

    async def monitor(self) -> None:
        """Periodic tick: decide between soft and hard reset."""
        try:
            while True:
                await asyncio.sleep(CHECK_INTERVAL)
                await self._tick()
        except asyncio.CancelledError:
            raise

    async def _tick(self) -> None:
        n = self.count()
        now = time.monotonic()
        if n <= 0:
            return

        if n >= HARD_THRESHOLD and (now - self._last_soft) >= HARD_AFTER_SOFT_SEC:
            self.hard_resets += 1
            self._last_hard = now
            log.error(
                "autorecover: %d upstream errors in %ds window -> HARD reset "
                "(exiting for container restart)", n, int(ERROR_WINDOW))
            if self._hard_cb:
                self._hard_cb()
            return

        if n >= SOFT_THRESHOLD and (now - self._last_soft) >= CHECK_INTERVAL * 2:
            self.soft_resets += 1
            self._last_soft = now
            log.warning(
                "autorecover: %d upstream errors in %ds window -> SOFT reset "
                "(clear blacklist/cooldown/pool, refresh CF domains)",
                n, int(ERROR_WINDOW))
            if self._soft_cb:
                try:
                    await self._soft_cb()
                except Exception as exc:
                    log.error("autorecover: soft reset failed: %s", repr(exc))
            self.reset()


autorecover = AutoRecover()
