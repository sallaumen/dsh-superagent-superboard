# Reconnect depth review

Baseline: `d083c43`, WebKit at `http://localhost:4003/?repo=fixture%2Fvisual-cards-review`, 1600×900. The test server used an Ecto Sandbox transaction with one Running, Ready and Blocked task, plus 55 Queued tasks. The transaction was rolled back after server exit.

The browser scrolled the Queued lane to load all 55 tasks, then called `window.liveSocket.disconnect()` and `connect()` to simulate a lost LiveView socket. Browser network offline mode did not close the existing socket in this WebKit run, so the test used the LiveSocket methods. It did not simulate a machine-wide network outage.

| State | Loaded queued cards | Unique card IDs | Focus | Lane scrollTop |
|---|---:|---:|---|---:|
| Before disconnect | 55 | 55 | `column-queued-list` | 7124px |
| Reconnecting | 55 | 55 | `column-queued-list` | 7124px |
| Before fix, reconnected | 50 | 50 | `column-queued-list` | 7124px |
| After fix, reconnected | 55 | 55 | `column-queued-list` | 7124px |

The connection label showed `reconnecting` during disconnection and `live` after reconnection. The WebKit console had zero errors or warnings in the final run. Screenshots show the loaded viewport, the lost page before the fix, and the restored page after the fix. No real task was changed.
