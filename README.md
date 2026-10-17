# FuzzCode

An iOS control surface for AI coding workflows, with configurable model providers, conversation history, project reference retrieval, and remote agent integration scaffolding.

## Native iOS app

Open [ios/FuzzCode/FuzzCode.xcodeproj](ios/FuzzCode/FuzzCode.xcodeproj) in Xcode and select the **FuzzCode** scheme. The project targets iOS 17 and later. Select a simulator, or configure your development team to run on an iPhone.

See the [native setup and integration notes](ios/FuzzCode/README.md) for build commands and current limitations. Use **Chat → Project context** to configure per-conversation prompts and local reference sources.

The `src/` directory contains a separate React prototype. It is not the native application or a backend for executing coding agents.
