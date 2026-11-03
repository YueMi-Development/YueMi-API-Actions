# YueMi API Actions

Composite GitHub Actions and Forgejo Actions for interacting with YueMi API.

## Actions

| Action | What It Does | How to Call |
| :--- | :--- | :--- |
| **Kitsune Notify** | Registers a Kitsune version (`panel`) with the YueMi API. | `uses: YueMi-Development/YueMi-API-Actions/kitsune/notify@v1.0.0` |
| **Kitsune Upload** | Requests signed S3 URL, uploads release binary, and syncs metadata. | `uses: YueMi-Development/YueMi-API-Actions/kitsune/upload@v1.0.0` |
| **Spigot Notify** | Registers a Spigot build, auto-detects git commit/branch, and returns `build-number` & `version-id`. | `uses: YueMi-Development/YueMi-API-Actions/spigot/notify@v1.0.0` |
| **Spigot Upload** | Requests signed S3 URL, uploads server jar, and syncs metadata. | `uses: YueMi-Development/YueMi-API-Actions/spigot/upload@v1.0.0` |
