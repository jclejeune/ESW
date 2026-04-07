# ESW

**Type-safe HTML templates for Swift, compiled at build time.**

---

## Why ESW?

Write templates in familiar HTML syntax, compile them to Swift code at build time.

```html
<!-- Views/users.esw -->
<%!
var users: [User]
%>
<ul>
<% for user in users { %>
  <li><%= user.name %> — <%= user.email %></li>
<% } %>
</ul>
```

**Generates:**

```swift
func renderUsers(_ users: [User]) -> String {
    var _buf = ESWBuffer()
    _buf.append("<ul>")
    for user in users {
        _buf.append("<li>")
        _buf.appendEscaped(user.name)
        _buf.append(" — ")
        _buf.appendEscaped(user.email)
        _buf.append("</li>")
    }
    _buf.append("</ul>")
    return _buf.finalize()
}
```

**Benefits:**
- **Zero runtime overhead** — No template parsing, no file I/O, no cache
- **Type-safe** — Template variables are Swift variables. Typos are compiler errors.
- **XSS-safe by default** — All output is HTML-escaped. Raw output requires explicit opt-in.
- **Designer-friendly** — No DSL to learn. Just HTML with familiar ERB-style tags.

---

## Quick Start

### Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/alembic-labs/swift-esw", from: "0.1.0"),
]
```

### Choose Your Integration

### Option A: Swift Macros (Recommended)

**Framework-agnostic** — works with any Swift web framework.

Returns `String`, you wrap it with your framework's response builder:

```swift
targets: [
    .target(
        name: "App",
        dependencies: [
            .product(name: "ESW", package: "swift-esw"),
        ]
    ),
]
```

Build with `--disable-sandbox` to allow macro file reads:

```bash
swift build --disable-sandbox
```

### Option B: Build Plugin (Nexus-Coupled)

Auto-generates `Connection`-returning functions for **Nexus framework** only:

```swift
targets: [
    .target(
        name: "App",
        dependencies: [
            .product(name: "ESW", package: "swift-esw"),
        ],
        plugins: [
            .plugin(name: "ESWBuildPlugin", package: "swift-esw"),
        ]
    ),
]
```

### Your First Template

Create `Views/greeting.esw`:

```html
<%!
var name: String
%>
<h1>Hello, <%= name %>!</h1>
```

**Use with macros (framework-agnostic):**

```swift
import ESW

func greet(name: String) -> String {
    return #render("greeting.esw")
}
```

Wrap the result with whatever your framework provides:

```swift
// Nexus
conn.html(#render("greeting.esw"))

// Hummingbird
Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: #render("greeting.esw"))))

// Vapor
Response(body: .init(string: #render("greeting.esw")))
```

**Or with the build plugin (Nexus-coupled):**

```swift
return renderGreeting(conn: conn, name: "World")
```

---

## Syntax Reference

| Tag | Purpose | Example |
|-----|---------|---------|
| `<%= expr %>` | Output (HTML-escaped) | `<%= user.name %>` |
| `<%== expr %>` | Raw output (no escaping) | `<%== rawHTML %>` |
| `<% code %>` | Swift code | `<% if condition { %>` |
| `<%# comment %>` | Comment | `<%# This is a comment %>` |
| `<%!-- comment --%>` | Multi-line comment | `<%!-- Across\nlines --%>` |
| `<%%` | Literal `<%` | `<%%` renders as `<%` |
| `%%>` | Literal `%>` | `%%>` renders as `%>` |
| `<%! vars %>` | Template parameters | See below |
| `<.component />` | Component tag | See below |
| `<:slot></:slot>` | Named slot | See below |

### Template Parameters

Declare Swift variables in a front-matter block:

```html
<%!
var user: User
var posts: [Post]
var isAdmin: Bool = false
%>
<h1><%= user.name %></h1>
<% if isAdmin { %>
  <span class="badge">Admin</span>
<% } %>
```

### Control Flow

Standard Swift control structures:

```html
<% if user.isLoggedIn { %>
  <p>Welcome back!</p>
<% } %>

<% for post in posts { %>
  <article><%= post.title %></article>
<% } %>

<% switch user.role { %>
<% case .admin: %>
  <span>Admin</span>
<% case .editor: %>
  <span>Editor</span>
<% default: %>
  <span>Viewer</span>
<% } %>
```

### Whitespace

Control-only lines are automatically trimmed (no blank lines in output):

```html
<ul>
<% for item in items { %>
  <li><%= item.name %></li>
<% } %>
</ul>
```

Renders as:
```html
<ul>
  <li>Apple</li>
  <li>Orange</li>
</ul>
```

Force a blank line with `<%+`:

```html
<%+ someCode %>
```

---

## Component Tags

Build reusable UI components with self-closing tags.

### Basic Components

```swift
// App/Components/Button.swift
struct Button: ESWComponent {
    static func render(label: String, disabled: Bool = false) -> String {
        """
        <button\(disabled ? " disabled" : "")>\(ESW.escape(label))</button>
        """
    }
}
```

**Usage:**

```html
<.button label="Click me" />
<.button label={item.name} disabled />
```

Generates:

```swift
Button.render(label: "Click me", disabled: true)
```

### Component Slots

Pass content regions to components using slots:

```swift
struct Card: ESWComponent {
    static func render(
        title: String,
        header: String = "",       // Named slot
        footer: String = "",       // Named slot
        content: String = ""       // Default slot
    ) -> String {
        """
        <div class="card">
            <h2>\(ESW.escape(title))</h2>
            \(header)
            <div class="body">\(content)</div>
            \(footer)
        </div>
        """
    }
}
```

**Usage:**

```html
<.card title="User Profile">
  <:header>
    <h1><%= user.name %></h1>
    <small><%= user.title %></small>
  </:header>
  <p><%= user.bio %></p>
  <:footer>
    <small>Last updated: <%= user.updatedAt %></small>
  </:footer>
</.card>
```

**Slot rules:**
- Bare content outside `<>` goes to the default `content:` parameter
- `<:name>` regions map to named parameters
- Slots are passed in alphabetical order, then `content:` last

---

## Macros

ESW provides two Swift macros for template rendering.

### `#render` — File Templates

Reads a `.esw` file at compile time and expands to a `String`-returning closure:

```swift
let users = try await db.query(User.self).all()
let html = #render("users.esw")
```

Template variables are captured from the surrounding scope.

Wrap with your framework:

```swift
// Nexus
conn.html(#render("users.esw"))

// Hummingbird
Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: #render("users.esw"))))

// Vapor
Response(body: .init(string: #render("users.esw")))
```

**File resolution:** Searches `Views/<name>` and `<name>` up to 6 directory levels up.

### `#esw` — Inline Templates

For small templates:

```swift
let badge = #esw("""
    <span class="badge"><%= count %></span>
    """)
```

### Framework Integration

The macro returns `String` — wrap it with whatever your framework provides:

```swift
// Nexus
conn.html(#render("page.esw"))

// Hummingbird
Response(status: .ok, body: .init(byteBuffer: ByteBuffer(string: #render("page.esw"))))

// Vapor
Response(body: .init(string: #render("page.esw")))
```

**Note:** Macros require `--disable-sandbox` due to Swift's sandbox restricting file reads.

---

## Build Plugin

Auto-generates Swift functions from `.esw` files.

### Generated Functions

| Filename | Generated Function |
|----------|-------------------|
| `user_profile.esw` | `renderUserProfile(conn:...)` |
| `layout.esw` | `renderLayout(conn:...)` |
| `_user_card.esw` | `renderUserCard(conn:...)` + `_renderUserCardBuffer(...)` |

### Usage

```swift
return renderUserProfile(conn: conn, user: user, posts: posts)
```

**Partials** (files starting with `_`) get both `Connection`-returning and `String`-returning variants for embedding in parent templates.

---

## Layouts

Wrap page content in a consistent layout shell.

### Layout Template

```html
<!-- Views/layout.esw -->
<%!
var title: String
var content: String
%>
<!DOCTYPE html>
<html>
  <head>
    <title><%= title %></title>
    <link rel="stylesheet" href="/app.css">
  </head>
  <body>
    <%== content %>
  </body>
</html>
```

### Composition

```swift
let body = #render("user_profile.esw")
let page = #render("layout.esw")

// Wrap with your framework (Nexus example)
conn.html(page)
```

---

## Escaping

- `<%= %>` — HTML-escapes output (default)
- `<%== %>` — Raw output, no escaping

To embed pre-rendered HTML without double-escaping:

```html
<%= render(_renderCardBuffer(user: user)) %>
```

Or use raw output:

```html
<%== _renderCardBuffer(user: user) %>
```

---

## Asset Fingerprinting

Cache-bust static assets using `AssetManifest`.

### Create a Manifest

Build tools generate a mapping:

```json
{
  "app.css": "app-abc123.css",
  "app.js": "app-def456.js"
}
```

### Use in Templates

```swift
import ESW

let manifest = try AssetManifest(jsonPath: "public/manifest.json")

func assetPath(_ name: String) -> String {
    manifest.path(for: name)
}
```

```html
<link rel="stylesheet" href="<%= assetPath("app.css") %>">
<script src="<%= assetPath("app.js") %>"></script>
```

**Fallback:** Missing assets return the original name.

---

## Hot Reload

Auto-recompile `.esw` files during development.

### Setup

```bash
brew install fswatch
```

### Run the Watch Script

```bash
./scripts/dev_watch.sh
```

Watches all `.esw` files and runs `swift build` on changes.

---

## Error Messages

Compiler errors point to the `.esw` file:

```
Views/user_profile.esw:5:22: error: value of type 'User' has no member 'naem'
```

The macro also provides clear diagnostics:

```
error: #render expects a file path (e.g. #render("template.esw")), not inline HTML.
       Use #esw("...") for inline templates.
```

---

## Development

### Run Tests

```bash
swift test
```

### Test Build Plugin Fixture

```bash
cd Fixtures/PluginConsumer && swift run App
```

### Hot Reload Development

```bash
# Terminal 1: Watch ESW files
./scripts/dev_watch.sh

# Terminal 2: Run your app
swift run App
```

---

## Architecture

```
swift-esw/
├── Sources/
│   ├── ESW/                  # Runtime library
│   │   ├── ESWBuffer.swift    # String builder
│   │   ├── ESWComponent.swift # Component protocol
│   │   ├── AssetManifest.swift
│   │   └── Macros.swift       # Macro declarations
│   ├── ESWCompilerLib/       # Compiler core
│   │   ├── Tokenizer.swift    # Lexical analysis
│   │   ├── ComponentResolver.swift  # Component tree building
│   │   ├── CodeGenerator.swift       # Swift code generation
│   │   └── Compiler.swift
│   ├── ESWMacros/            # Macro implementations
│   ├── ESWCompilerCLI/       # Standalone CLI
│   └── ESWBuildPlugin/       # SPM plugin
├── Tests/                     # 179 tests
└── Fixtures/                  # Integration test app
```

### Compiler Pipeline

```
.esw source
    ↓
Tokenizer → Tokens
    ↓
WhitespaceTrimmer → Trimmed tokens
    ↓
AssignsParser → Parameters
    ↓
ComponentResolver → RenderNode tree
    ↓
CodeGenerator → Swift code
```

---

## Requirements

- Swift 6.3+
- macOS 14+

---

## License

MIT
