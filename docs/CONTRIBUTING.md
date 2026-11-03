# Contributing to DroidLink

Thank you for your interest in contributing to DroidLink! 🎉

## Getting Started

1. **Fork** the repository
2. **Clone** your fork:
   ```bash
   git clone https://github.com/<your-username>/DroidLink.git
   cd DroidLink
   ```
3. **Create a feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Setup

### macOS App
- Requires Xcode 15.0+
- Open `mac/DroidLink/DroidLink.xcodeproj`
- Select the DroidLink scheme and build (⌘B)

### Android App
- Requires Android Studio Ladybug+ or Gradle 8.9+
- Open the `android/` directory in Android Studio
- Sync Gradle and build

### Prerequisites
- JDK 17+
- Android SDK 35
- `adb` (Android Platform Tools): `brew install android-platform-tools`

## Code Style

### Swift (macOS)
- Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- Use SwiftLint rules (config in `.swiftlint.yml`)
- 4-space indentation
- Max line length: 120 characters

### Kotlin (Android)
- Follow [Kotlin Coding Conventions](https://kotlinlang.org/docs/coding-conventions.html)
- Use ktlint for formatting
- 4-space indentation
- Max line length: 120 characters

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add clipboard image sync support
fix: resolve crash on Android 14 when notification access is revoked
docs: update setup guide for wireless mode
refactor: extract video decoder into separate service
test: add unit tests for protocol message parsing
```

## Pull Request Process

1. Ensure your code compiles on both platforms
2. Add/update tests for new functionality
3. Update documentation if you've changed APIs or features
4. Fill out the PR template
5. Request review from maintainers

## Issue Templates

- **Bug Report:** Include device info, steps to reproduce, expected vs actual behavior
- **Feature Request:** Describe the use case, proposed solution, and alternatives considered

## Architecture Guidelines

- **Services** handle business logic and side effects
- **Views** are purely UI, driven by `@Observable` service state
- **Models** are simple data structs (Codable/Serializable)
- Keep the protocol layer platform-independent (defined in `protocol/`)

## Areas for Contribution

| Area | Difficulty | Description |
|------|-----------|-------------|
| Documentation | 🟢 Easy | Improve setup guides, add screenshots |
| UI Polish | 🟡 Medium | SwiftUI/Compose UI improvements |
| File Transfer | 🟡 Medium | Progress tracking, resume support |
| Notifications | 🟡 Medium | App icon extraction, rich content |
| Video Pipeline | 🔴 Hard | Codec optimization, latency reduction |
| Virtual Display | 🔴 Hard | Multi-window Android apps |

## Code of Conduct

Be respectful, inclusive, and constructive. We're all here to make Android + Mac work better together. 🤝

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
