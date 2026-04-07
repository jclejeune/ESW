# Content Slots for ESW Component Tags

**Date:** 2026-04-07  
**Status:** Approved  
**Scope:** Named and default content slots for `<.component>` tags

---

## Context

ESW gained component tag syntax (`<.button label="Click" />`) in the session preceding this spec. Self-closing components work end-to-end. This spec covers the next step: content slots — the ability to pass rendered HTML fragments as parameters to a component, using `<.card>...</.card>` syntax with optional named slot regions.

---

## Goals

- `<.card>inner content</.card>` passes a compiled `content: String` argument
- `<:header>...</:header>` inside a component body defines a named slot
- Bare content outside named slots maps to the implicit `content:` slot
- Slot content supports full ESW syntax: `<%= %>`, `<% %>`, nested `<.components>`
- All structural errors (unterminated tags, duplicate slots, orphan slots) surface at build time pointing at the `.esw` file line

---

## Non-Goals

- Self-closing slot tags (`<:header />`) — not supported; omit the slot if content is empty
- Runtime slot resolution — everything is compile-time
- Streaming or lazy slot evaluation

---

## Syntax

```html
<!-- Self-closing (unchanged) -->
<.button label="Click me" />

<!-- Default slot only -->
<.card>
  <p>Body content here</p>
</.card>

<!-- Named slots only -->
<.layout>
  <:head><title>Hello</title></:head>
  <:body><p>Content</p></:body>
</.layout>

<!-- Named slots + default content -->
<.card title="Hello">
  <:header>Welcome</:header>
  <p>This is bare content → goes to content:</p>
</.card>

<!-- Full ESW syntax inside slots -->
<.card>
  <:header><%= user.name %></:header>
  <% for item in items { %>
    <li><%= item.title %></li>
  <% } %>
</.card>
```

---

## Pipeline

```
Tokenizer → WhitespaceTrimmer → AssignsParser → ComponentResolver → CodeGenerator
```

`ComponentResolver` is the new stage. It takes `[Token]` (after assigns are stripped) and returns `[RenderNode]`.

---

## Token Layer

Two new `Token` cases added to `Token.swift`:

```swift
case slotOpen(name: String, metadata: Metadata)   // <:header>
case slotClose(name: String, metadata: Metadata)  // </:header>
```

Tokenizer detection order (inserted before `<%` check, after `<.` / `</.` checks):

1. `</:` → `.slotClose` — read name until `>`, consume `>`
2. `<:` → `.slotOpen` — read name until `>`, consume `>`

Slot names follow component name rules: letters, digits, hyphens.

Example token stream for `<.card title="Hello"><:header>Hi</:header><p>Body</p></.card>`:

```
.componentTag(name: "card", attributes: [{title: .string("Hello")}], selfClosing: false)
.slotOpen(name: "header")
.text("Hi")
.slotClose(name: "header")
.text("<p>Body</p>")
.componentClose(name: "card")
```

---

## RenderNode Tree

New file `Sources/ESWCompilerLib/RenderNode.swift`:

```swift
public indirect enum RenderNode {
    case token(Token)
    case component(ComponentNode)
}

public struct ComponentNode {
    public let name: String
    public let attributes: [ComponentAttribute]
    /// Named slot content, keyed by slot name. Ordered pairs — not a Dictionary.
    /// Order preserved from source; codegen sorts alphabetically at emit time.
    public let namedSlots: [(name: String, nodes: [RenderNode])]
    /// Bare content outside any named slot → emitted as `content:` argument.
    /// Empty array means no `content:` argument is emitted.
    public let defaultSlot: [RenderNode]
    public let metadata: Metadata
}
```

`namedSlots` is stored as ordered pairs (not `Dictionary`) so insertion order is preserved and tests are deterministic. The codegen sorts alphabetically at emit time.

---

## ComponentResolver

New file `Sources/ESWCompilerLib/ComponentResolver.swift`.

Uses `swift-algorithms` (`apple/swift-algorithms`) for sequence operations in the slot-splitting logic.

**Algorithm:**

```
resolve([Token]) → [RenderNode]:
  walk tokens linearly
  for each token:
    if .componentTag(selfClosing: true):
      emit .token(t)
    if .componentTag(selfClosing: false):
      collect tokens until matching .componentClose (depth-tracked)
      split collected tokens into namedSlots + defaultSlot
      recursively resolve each region
      emit .component(ComponentNode(...))
    if .componentClose with no matching open:
      throw .unmatchedComponentClose
    if .slotOpen / .slotClose outside a component:
      throw .slotOutsideComponent
    else:
      emit .token(t)
```

**Depth tracking for nested components:**  
When scanning for the matching `.componentClose(name: "card")`, maintain a depth counter. Increment on `.componentTag(name: "card", selfClosing: false)`, decrement on `.componentClose(name: "card")`. Stop when depth reaches zero.

**Slot splitting:**  
Within the collected inner tokens, walk linearly. When outside any `slotOpen/slotClose` pair, accumulate into `defaultSlot` tokens. When inside a `slotOpen/slotClose` pair, accumulate into the named slot's token list. Throw `.duplicateSlot` if a name appears twice.

---

## Error Types

New cases in `ESWComponentError` (new enum in `Errors.swift`):

```swift
public enum ESWComponentError: Error, Equatable {
    case unterminatedComponent(file: String, line: Int, column: Int)
    case unmatchedComponentClose(file: String, line: Int, column: Int)
    case unterminatedSlot(file: String, line: Int, column: Int)
    case unmatchedSlotClose(file: String, line: Int, column: Int)
    case duplicateSlot(name: String, file: String, line: Int)
    case slotOutsideComponent(file: String, line: Int, column: Int)
}
```

All errors surface at `ComponentResolver` time. The CLI (`ESWCompilerCLI/main.swift`) adds a `catch ESWComponentError` branch emitting Xcode-compatible `file:line:col: error:` diagnostics.

---

## Code Generation

`CodeGenerator` changes:

- Constructor takes `renderNodes: [RenderNode]` instead of `tokens: [Token]`
- `emitTokenBody` renamed to `emitNodeBody`, handles both `RenderNode` cases
- `.token(t)` falls through to the existing token switch (unchanged)
- `.component(node)` generates the component call with slot IIFEs

**Argument ordering rule:**  
`attributes (source order in tag)` → `named slots (alphabetical)` → `content:` (last, omitted if empty)

**Empty named slots:** A slot written as `<:header></:header>` (explicitly present but empty) still emits its argument with an empty string. A slot not written at all is not emitted. Component authors use default parameter values for optional named slots.

**Generated output for `<.card title="Hello"><:header>Hi</:header><p>Body</p></.card>`:**

```swift
_buf.appendUnsafe(Card.render(
    title: #"Hello"#,
    header: {
        var _buf = ESWBuffer()
        _buf.append(#"Hi"#)
        return _buf.finalize()
    }(),
    content: {
        var _buf = ESWBuffer()
        _buf.append(#"<p>Body</p>"#)
        return _buf.finalize()
    }()
))
```

Slot IIFEs are generated by recursively calling `emitNodeBody` into a fresh line buffer. Source location directives are suppressed inside slot IIFEs.

---

## Component Protocol

`ESWComponent.swift` documents the argument ordering convention:

```swift
// Slots declared alphabetically, content: last
struct Card: ESWComponent {
    static func render(
        title: String,
        header: String,          // named slot — alphabetical
        content: String = ""     // default slot — always last, optional default
    ) -> String { ... }
}
```

The `ESWComponent` protocol itself is informational — Swift's type system enforces the contract at the call site. The protocol's `render()` stub is documentation, not enforcement.

---

## Compiler.swift Changes

One new line between the assigns filter and `CodeGenerator` init:

```swift
let bodyTokens = trimmedTokens.filter { /* strip assigns */ }
let renderNodes = try ComponentResolver.resolve(bodyTokens)   // ← new
let generator = CodeGenerator(renderNodes: renderNodes, ...)
```

---

## Package.swift Changes

Add `swift-algorithms` as a dependency:

```swift
.package(url: "https://github.com/apple/swift-algorithms", from: "1.2.0")
```

Add to `ESWCompilerLib` target dependencies:
```swift
.product(name: "Algorithms", package: "swift-algorithms")
```

---

## Testing

### `ComponentResolverTests` (new)
Feed flat `[Token]` arrays, assert on `[RenderNode]` output:
- Self-closing component passes through as `.token`
- Open component with no content → `ComponentNode` with empty slots
- Single named slot
- Multiple named slots
- Bare content only → `defaultSlot` populated, `namedSlots` empty
- Mixed named + bare
- Nested component inside slot content (recursive resolve)
- All six `ESWComponentError` cases

### `ComponentTagTests` (expand)
Codegen-level assertions:
- Named slot generates alphabetically-ordered IIFE arguments
- Empty `defaultSlot` omits `content:` argument
- Attributes + named slots combined
- Nested component inside slot content compiles through

### `TokenizerTests` (expand)
- `<:header>` produces `.slotOpen(name: "header")`
- `</:header>` produces `.slotClose(name: "header")`
- Slot inside component token sequence
- Slot name with hyphens

---

## Files Changed

| File | Change |
|---|---|
| `Sources/ESWCompilerLib/Token.swift` | Add `.slotOpen`, `.slotClose` cases |
| `Sources/ESWCompilerLib/Tokenizer.swift` | Detect `<:` and `</:` sequences |
| `Sources/ESWCompilerLib/Errors.swift` | Add `ESWComponentError` enum |
| `Sources/ESWCompilerLib/RenderNode.swift` | New — `RenderNode`, `ComponentNode` |
| `Sources/ESWCompilerLib/ComponentResolver.swift` | New — resolver pass |
| `Sources/ESWCompilerLib/CodeGenerator.swift` | Takes `[RenderNode]`, adds `emitNodeBody` |
| `Sources/ESWCompilerLib/Compiler.swift` | Add resolver step |
| `Sources/ESW/ESWComponent.swift` | Document argument ordering convention |
| `Sources/ESWCompilerCLI/main.swift` | Handle `ESWComponentError` in catch block |
| `Package.swift` | Add `swift-algorithms` dependency |
| `Tests/ESWCompilerLibTests/ComponentResolverTests.swift` | New test suite |
| `Tests/ESWCompilerLibTests/ComponentTagTests.swift` | Expand existing suite |
| `Tests/ESWCompilerLibTests/TokenizerTests.swift` | Expand existing suite |
| `Tests/ESWCompilerLibTests/WhitespaceTrimmerTests.swift` | Add `.slotOpen`, `.slotClose` to `kinds()` exhaustive switch |
