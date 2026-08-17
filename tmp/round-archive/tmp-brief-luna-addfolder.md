Operator task (Luna): reproduce a user-reported crash. App: "Agent Studio Debug jp6s", PID 77309, ALREADY RUNNING — do not launch anything, do not quit it. Work on the second monitor; do not steal the user's foreground beyond the minimum.

Report: user clicked "Add Folder" (repo sidebar) and says the app crashed. Process 77309 is still alive, so either a different instance died or the failure is visual/hang, or the crash spawned a relaunch.

Do:
1. peekaboo see --app "PID:77309" --json — capture current UI state (screenshot + AX tree). Confirm the window exists and which sidebar surface is shown.
2. Locate the Add Folder affordance (sidebar + button or File menu "Add Folder…"). Invoke it. If a file chooser appears, select /Users/shravansunder/Documents/dev/project-dev/agent-studio.sidebar-grouping/tmp/luna-addfolder-fixture (create that dir with `git init` FIRST so it is a real repo).
3. Observe for 30s: screenshot bursts; check `pgrep -lf "AgentStudio Debug jp6s"` for PID change (relaunch = crash), check ~/Library/Logs/DiagnosticReports for new AgentStudio*.ips, and `log show --last 5m --predicate 'process == "AgentStudio"' | grep -iE "assert|fatal|crash"` for traps.
4. Repeat the click once more with a NON-git folder (plain mkdir) — the registration validation path differs and is fresh code (#299/#307).
5. Write findings to tmp-luna-addfolder-RESULT.md: reproduced or not, PID stability, any .ips paths, screenshots saved under tmp-screenshots/luna-addfolder/. Do NOT fix anything.
