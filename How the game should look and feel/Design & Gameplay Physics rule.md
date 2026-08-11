# Design & Gameplay Physics Brief — for Claude (or any AI working on TableSoccer)

**FIRST: GO THROUGH THE CODEBASE** — read the project scripts and understand how the game currently works, if you haven't already. Don't work blind.

> **THE RULE, ABOVE ALL ELSE:** WATCH THE VIDEO (`Record_2026-08-05-22-04-56_b52afecc81869d1e5d72c024d8519dc3.mp4`) AND LOOK AT THE SCREENSHOTS IN THIS SAME FOLDER. The video IS the gameplay spec — the feel, the physics, the quirks. If you watched it, you know exactly how the game should play. Recreate the gameplay feel and physics from it — not from imagination.

**HOW TO WORK:**
- **USE THE GODOT 2D EDITOR VISUALLY** — screenshots + node tools. You are allowed (encouraged) to recreate the Plato look by seeing and placing, not only scripting.
- **Design system & tokens are DYNAMIC** — update them as you design; don't follow them rigidly.
- **NO play-testing needed** — deliver the job done in ONE pass.
- **Take your time; do it in parts** — one section at a time.
- **IMPORTANT — SET UP GODOT + THE MCP BRIDGE FIRST** on the machine you're working on: Godot 4.7 and the godot-ai MCP plugin must be installed and connected before you start (the visual editor workflow depends on it).

-----------

## Visual / Design

You are taking over the **visual/design layer** of a Godot 4.7 table-soccer game that mimics **Plato Table Soccer (Tactical mode)**.  Your job: make the game look similar to table soccer by plato (WATCH THE VIDEO AND LOOK AT THE PICTURES IN THE SAME FOLDER)

> **THE DESIGN GOAL, ABOVE ALL ELSE:** the finished game must look and feel **as close to the real Plato Table Soccer as possible** — same visual identity, same proportions, same vibe. When you are deciding between two options and one brings the game closer to Plato's look, choose that one, always. The real Plato screenshot (user-provided, measured in §5)

1. YOU CAN UPDATE THE DESIGN SYSTEM AND DESIGN TOKEN , U DONT HAVE TO FOLLOW IT AS ITS DYNAMIC

1. **Screens are portrait** — design for 1080×1920 at `keep` aspect; never assume the full canvas is visible on odd windows (letterbox handles it).
2. **Match the real Plato** — when in doubt, measure the reference screenshot with before inventing.
3. WATCH THE 2MIN VIDEO AND FOLLOW ITS DESIGN AND QUIRKS
4.THE VIDEO CAN BE USED FOR RECRETING THE GAMEPLAY IF YOU FEEL THE GAMEPLAY DOESNT MEET THE STANDARD
5. YOU MUST DO THE WORK, DONT DEFFRED OR JUST DIAGNOSE AND PUSH.

-----------

## Gameplay / Physics

You are taking over the **gameplay/physics layer** of the Godot 4.7 table-soccer game that mimics **Plato Table Soccer (Tactical mode)**.

1. **WATCH THE VIDEO + SCREENSHOTS FIRST** — recreate the gameplay feel and physics from them. If you watched the video you will know ALL of the points below — it's all there.

2. **6 caps per team, goalkeeper is bigger**: each team gets 6 caps — 5 normal-sized + 1 BIGGER cap that is the goalkeeper. The GK's larger size must be real physics (bigger collider), not just a visual change.

3. **Everything wired**: design (visuals), gameplay (physics/mechanics), and backend (networking/state) must all be connected and working together — no standalone pieces.

4. **Kickoffs**: after a goal, both teams return to their formation, the ball resets to the center spot, and the conceding team kicks off.

5. **Holder faces the goal**: when a cap has the ball, it rotates to face the opponent's goal — just like in Plato Table Soccer.

6. **Crowd sound**: ambient crowd noise during play, and crowd screaming/cheering when a goal is scored.
