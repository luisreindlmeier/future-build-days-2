# Local demo setup

The missing Java `data` source package has been restored from the original backend
folder. The ignore rule is now `/data/`, so runtime memory stays ignored while Java
source files are included.

Verified: 14 Java tests, 27 Python tests, and the full local HTTP integration check
pass. All four customers reach READY in rule-based mode. The integration check also
covers alias commits, duplicate prevention, verification, refreshed scenarios, dropping
an action and resetting progress. Live AI and browser planner interactions have not
been tested here.

Use one laptop and this integrated checkout. Java 21, Maven, Python 3.9+ and a browser
are enough; IntelliJ and VS Code are optional. Commands below run in bash (macOS/Linux
or WSL). On Windows without WSL, use `py` for Python and the equivalent PowerShell
copy commands. All three terminals must use the same machine/environment.

## 1. Check the installation

From the repository root:

```bash
java -version
mvn -version
python3 --version
```

Use Java 21 for the tested setup; `mvn -version` must also report it. The first Maven
run downloads dependencies, so do this before arriving at the venue:

```bash
cd backend
mvn test
mvn package
cd ..
```

The Python bridge uses the standard library; no pip installation is required.
For a repeatable end-to-end rehearsal without changing your demo state, run from the
repository root after building the jar:

```bash
python3 tools/test_integration.py
```

This starts all three services on temporary ports, uses temporary progress storage,
forces rule-based agents, exercises the commit/verify/drop/reset flow, and stops its
servers afterward. It uses `JAVA_HOME/bin/java` when `JAVA_HOME` is set.

## 2. Configure AI (optional for the agents)

Copy these files only if the destination does not already exist:

```bash
cp -n prediction-agent/.env.example prediction-agent/.env
cp -n projects-section/js/secrets.example.js projects-section/js/secrets.js
```

Edit `prediction-agent/.env` locally and replace the placeholder after `HIP_API_KEY=`
with the demo key. Leave it empty for rule-based mode. Do not leave `your-key-here` as
its value: any nonempty value makes the health endpoint report that a key is configured.
Keep the supplied HIP model and base URL unless your gateway requires different ones.

Set `AI_KEY` in `projects-section/js/secrets.js` for the separate projects planner.
An empty key still lets you open the page but does not enable its AI planner. Both
files are ignored by Git. Never paste keys into chat or commit them. The projects key
is used in browser code and is visible to visitors; this local demo configuration is
not a server-side secret deployment.

## 3. Start three terminals

Terminal 1, repository root:

```bash
python3 backend/tools/kairos_server.py --agent-dir prediction-agent
```

This listens at `http://localhost:8090`. Startup prints the engine version and whether
a key is configured. To force offline text even if `.env` has a key:

```bash
HIP_API_KEY= python3 backend/tools/kairos_server.py --agent-dir prediction-agent
```

Terminal 2, repository root:

```bash
cd backend
java -jar target/wealth-tree-backend-0.1.0.jar
```

For development, `mvn spring-boot:run` also works. The backend listens on port 8080
and prepares all four customers in the background. Wait for READY rather than assuming
30 seconds is always sufficient; live calls can take longer or fall back.

Terminal 3, repository root:

```bash
python3 -m http.server 5500 --bind 127.0.0.1 --directory projects-section
```

Open:

<http://localhost:5500/index.html?customer=http://localhost:8080/api/users/maya/kairos>

Replace `maya` with `lena`, `alex`, or `max`. Open through HTTP, not `file://`.

## 4. Verify the real connection

From another terminal, repository root:

```bash
python3 tools/check_demo.py
```

This reads bridge health, waits for all four assessments, checks the Kairos response,
and checks the mapping and static page. It does not change customer progress.
It prints each agent's actual `source`. `live_ai: true` means a key is configured;
only `source: ai` on returned predictions/actions confirms a live AI result.
`fallback` or `ai_partial` means rules supplied some or all text. Inspect the response's
`problems` / `validation` and the local `prediction-agent/guardrail.log` if needed.

The projects planner calls AI separately: open the page, enter a project and request
a plan to verify that key and the venue's connection. Python health does not verify it.

## 5. Rehearse the tree interaction

These commands change Maya's demo progress:

```bash
curl http://localhost:8080/api/users/maya/actions/mapping
curl -X POST http://localhost:8080/api/users/maya/actions/limit_eating_out/commit
curl -X POST 'http://localhost:8080/api/users/maya/advance-month?months=3'
curl http://localhost:8080/api/users/maya/tree
curl http://localhost:8080/api/users/maya/prediction
```

The last request may be RUNNING while the changed intake is processed. Poll until READY.
See [the mapping contract](ACTION_MAPPING.md) before wiring a commit button.

Immediately before the pitch, reset everyone to month 0 and warm up again:

```bash
curl -X POST http://localhost:8080/api/demo/reset
python3 tools/check_demo.py
```

Reload the projects page after reset or progress changes; it loads customer data when
opened. Memory is stored under `backend/data/` when started from `backend/` and survives
restarts on that machine. Keep the same working directory each time.

## Troubleshooting and fallback

- Port already in use: stop the old process with Ctrl+C. The instructions use 8090,
  8080 and 5500. Backend bridge URL is configured in `backend/src/main/resources/application.properties`.
- Prediction UNAVAILABLE: check that the Python bridge is running with the right
  `--agent-dir`; inspect `/health`. The backend retries unavailable results after
  ten seconds. Restart the backend after changing bridge credentials to clear cached text.
- No internet or gateway failure: the Python agents use rule-based text. The tree,
  scanner and progress continue locally. The projects AI planner needs a connection.
- Bridge stopped: backend forecast endpoints have a Java fallback, but `/kairos`
  still needs the Python assessment. Keep the bridge running for the projects demo.
- Offline venue: build the jar ahead of time and rehearse with `HIP_API_KEY=`. Cached
  Maven dependencies alone do not provide the projects planner's external AI service.
- Slide numbers: use the current READY engine results. Engine 1.1 differs from older
  simulations; do not reuse the old Maya 27% figure. Check values again after reset.

For an online deployment, serve the frontend over HTTPS, proxy browser AI through a
server-held secret, configure API URLs/CORS and persistent state, and put the Python
bridge on a private reachable interface. The current bridge binds to loopback and the
backend has no authentication; this guide prepares a local demo, not a public deployment.
