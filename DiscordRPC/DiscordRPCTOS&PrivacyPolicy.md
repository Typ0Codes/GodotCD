# GodotCD — Terms of Service & Privacy Policy

**Project:** GodotCD  
**Repository:** https://github.com/Typ0Codes/GodotCD  
**Feature:** Discord Rich Presence  
**Effective Date:** June 29, 2026

---

## Terms of Service

### 1. About This Software

GodotCD is a free, open-source CD player application for Linux built with Godot 4. The Discord Rich Presence feature optionally displays your current playback activity (e.g. the CD you are listening to) on your Discord profile.

### 2. Use at Your Own Discretion

GodotCD is provided **as-is**, free of charge, with no warranties expressed or implied. By using this software, you accept that:

- The software is provided without any guarantee of fitness for a particular purpose, stability, or continued maintenance.
- The developers are not liable for any damages arising from the use or inability to use the software.
- Discord Rich Presence functionality depends on Discord's own platform and client; GodotCD is not affiliated with or endorsed by Discord Inc.

### 3. Open Source License

GodotCD is open-source software. Refer to the repository's LICENSE file for the terms under which you may use, modify, and distribute the software.

### 4. Third-Party Services

The Rich Presence feature communicates with the **Discord client installed on your machine** via Discord's local IPC socket. This communication is entirely local — no data is sent to any server operated by this project.

You remain subject to [Discord's own Terms of Service](https://discord.com/terms) when using their platform.

### 5. Changes to These Terms

These terms may be updated to reflect changes in the software. The latest version will always be available in the project repository.

---

## Privacy Policy

### Our Commitment

**GodotCD does not collect, store, transmit, or share any personal data — ever.**

There are no servers, no databases, no analytics, no telemetry, and no accounts. This is a local desktop application.

### What the Rich Presence Feature Does

When Discord Rich Presence is enabled, GodotCD communicates with the **Discord desktop client running on your own machine** via a local IPC (inter-process communication) socket. This tells Discord what you are currently playing so it can display that information on your profile to your Discord friends.

This is **entirely local**. GodotCD itself does not transmit anything over the internet.

### What GodotCD Does NOT Do

- Does not collect personal information
- Does not track usage or behavior
- Does not send analytics or telemetry
- Does not use cookies or identifiers
- Does not connect to any external servers
- Does not store any data on disk beyond normal application state (e.g. window size, volume)

### Discord's Role

Once GodotCD passes presence data to the local Discord client, that data is governed entirely by **Discord's Privacy Policy** (https://discord.com/privacy). GodotCD has no control over how Discord handles or displays that information on their platform.

### Contact

This is an open-source project. If you have questions or concerns, open an issue at:  
https://github.com/Typ0Codes/GodotCD/issues

---

*GodotCD is an independent open-source project and is not affiliated with Discord Inc. or Godot Engine.*
