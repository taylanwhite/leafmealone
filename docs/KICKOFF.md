# Prompts for Cursor

Paste these into a Cursor agent chat. They assume `AGENTS.md`, the rules in `.cursor/rules/`, and your own `local-me.mdc` are in place, so they stay short and point the agent at the docs instead of repeating them.

---

## 1. M0 setup (Taylan, once)

```
Read AGENTS.md, docs/GAME.md, docs/PLAN.md, docs/NETCODE.md, docs/PLATFORMS.md, and docs/DECISIONS.md fully.

We're starting milestone M0 on my Mac. Go through the M0 tasks in order. For tasks marked (human), stop and give me exact step-by-step instructions for what to click, then wait for me to say done before continuing. For the rest, do them yourself, run the project through the Godot MCP after each one, and commit each task separately with the [SHARED] prefix.

When you verify the GodotSteam install, show me the exact output. If SteamMultiplayerPeer is missing, stop and explain the fallback before doing anything else.

At the end, check off the M0 tasks you completed in docs/PLAN.md, push, and give me a short summary of anything that surprised you or that my brother needs to know before he clones.
```

## 2. Onboarding (brother, once)

```
Read AGENTS.md, docs/GAME.md, docs/PLAN.md, docs/NETCODE.md, docs/PLATFORMS.md, docs/DECISIONS.md, and docs/HANDOFFS.md fully.

I just cloned this repo on my Mac and I own the PLAY lane. Check my setup: confirm local-me.mdc exists and says PLAY, confirm the Godot MCP can run the project with no errors, and confirm git and Git LFS are working by showing me the last five commits and git lfs ls-files. Then check off the last M0 task in docs/PLAN.md, commit with [SHARED], and push.

Finally, summarize in a few sentences what PLAY owns, what I'm not allowed to touch, which design questions are still open that affect my work, and what my first M1 tasks are.
```

## 3. Session start (both, every time)

```
Start a session. Pull with rebase and tell me if anything conflicts. Read AGENTS.md, the current milestone in docs/PLAN.md, and any open entries in docs/HANDOFFS.md addressed to my lane.

Tell me which unchecked task in my lane you plan to take next and your plan for it in five lines or fewer, including any open design question (OQ id) it touches and how you'll keep that flexible. If something in HANDOFFS is blocking the other lane, put that first. Wait for my go-ahead before writing code.
```

## 4. Do the task (after you approve the plan)

```
Go. Keep commits small. After each change, run the project through the Godot MCP and fix any errors or warnings you introduced. If this touches multiplayer, run the smoke test before committing. When the task is done, tell me exactly what you ran, what I should check by hand with multiple instances, and anything you weren't able to verify.
```

## 5. Session end (both, every time)

```
Wrap up the session. Make sure everything is committed with the right lane prefix. Check off only the tasks in my lane that are actually done and verified. Add an entry to docs/DECISIONS.md for any technical decision we made today, list any game design decisions I made so I can put them in the workbook, and add anything we need from the other lane to docs/HANDOFFS.md. Pull with rebase, run the project once more, and push. Then give me a three-line summary I can send my brother.
```

## 6. First M1 session for NET

```
Start M1 for the NET lane. Your first job, before anything else, is the stub task at the top of M1 in docs/PLAN.md: create net/net.gd (autoload Net), net/campaign.gd (autoload Campaign), and net/components/net_smoother.gd with the exact signatures from docs/NETCODE.md, including the later-milestone additions, as stubs that compile and do nothing harmful. Push that as its own commit so PLAY can build against it today. Then continue with the ENet implementation of Net.
```

## 7. First M1 session for PLAY

```
Start M1 for the PLAY lane. Pull first to get the Net, Campaign, and NetSmoother stubs from NET. If they aren't pushed yet, start with levels/world.tscn and a local-only player controller with the swappable camera rig, and code against the APIs in docs/NETCODE.md so nothing changes when the real implementation lands. Don't create or edit anything under net/.
```

## 8. The workbook changed

```
I updated design/leaf-me-alone-workbook.xlsx. Run python3 design/export_balance.py and show me the diff to core/balance.gd. Then read the workbook's Decisions & Log, Game Vision, and Open Questions sheets with Python and compare them to docs/GAME.md. List what's new or changed, update docs/GAME.md to match (Confirmed items only go in the canon section), and tell me if any change affects work already done or planned in docs/PLAN.md. Commit with [SHARED].
```

## 9. Cross-play test (from M3)

```
Prepare a cross-play test. Run tools/export.sh to build macOS and Windows, confirm both builds exist, and give me a checklist following docs/PLATFORMS.md: what to copy to the Windows PC, which machine hosts first, what to check in each zone, what to check in the debug overlay, and what to swap for the second round. After I report results, file anything broken as tasks in the right lane or HANDOFFS entries.
```

## 10. Cross-lane review (either, once per milestone)

```
Review every commit from the other lane since the start of this milestone against AGENTS.md, docs/NETCODE.md, docs/GAME.md, and the rules in .cursor/rules/. List anything that breaks the authority rules, touches files outside that lane, calls Steam or ENet outside net/, hardcodes balance values, invents canon, steps a shared simulation frame by frame, invents uids, or skips the smoke test. Don't change any of their files. For each real problem, add an entry to docs/HANDOFFS.md addressed to their lane and push.
```

## 11. Merge conflict

```
I have a merge conflict. Show me which files conflict and, for each one, which lane owns it. Don't resolve anything in a file my lane doesn't own; tell me to coordinate with my brother instead. For files I own, project.godot, or export_presets.cfg, explain both sides of each conflict, propose a resolution that keeps both changes where possible, and wait for my approval before applying it. After resolving, run the project and the smoke test.
```

## 12. Something feels wrong in multiplayer

```
In multiplayer, [describe what you saw, on which instance, host or client, Mac or Windows, which zone, and roughly when]. Before changing code, read docs/NETCODE.md and explain which peer is authoritative for the thing that looks wrong and how its state reaches the other peers. Then list the most likely causes in order and the cheapest way to confirm each one, such as a log line or a debug overlay value. Wait for me to confirm the cause before fixing it.
```
