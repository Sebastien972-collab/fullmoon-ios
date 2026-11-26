# NoctisChatUI

This local presentation package adapts the native chat, composer, drawer and
glass control patterns from:

- Project: https://github.com/bryanrg22/chatgpt-ios-ui
- Revision: `dc6e6a52b14a67051f6534cc674cc32ddd9cb9d1`
- Author: Bryan Ramirez-Gonzalez and contributors
- Original license: MIT, retained in full in `LICENSE` and distributed with the
  package resources as `ChatGPTUI-MIT.txt`.

The adaptations derive from `ComposerTextView.swift`, the chat/composer/drawer
sections of `ChatGPTView.swift`, and the glass controls in `Design.swift`.
The composer now uses Dynamic Type. Navigation follows the horizontal size
class, with a compact drawer and a regular NavigationSplitView. History,
selection, deletion, generation, cancellation, settings, Markdown rendering and
storage belong to the host application.

The upstream optimistic chat state, demonstration conversations, synthetic
responses, model catalogs, network features, voice/media simulations, widgets,
brand names and logo resources are not included. The host supplies its real
transcript and status views. This package has no external dependencies and
does not implement inference, persistence or network requests.

The public Foundation types and resource attribution are available on all
declared platforms. The SwiftUI chat shell is compiled only for iOS; existing
macOS and visionOS interfaces remain host responsibilities.

## Tabler Icons

The chat controls and lunar mark use [Tabler Icons v3.34.1](https://github.com/tabler/tabler-icons/tree/v3.34.1), by Paweł Kuna. The bundled SVGs preserve the upstream paths and use a solid template color so SwiftUI can tint them. The iOS launcher uses the same `moon-stars` paths with a lighter stroke and backgrounds for the light, dark and tinted appearances. The release's complete MIT notice ships in `TablerIcons-MIT.txt`.
