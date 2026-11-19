# Credits

**Parsec Merchant** is a native macOS remake of **Space Trader**, and is based on Space Trader by Pieter Spronck.

## Original game: Space Trader for Palm OS (2000–2005)
- **Pieter Spronck**: design and original code. https://www.spronck.net/spacetrader/
- **Sam Anderson** and **Samuel Goldstein**: additional coding.
- **Matt Lee**: DopeWars, from which parts of the original trading code were derived.

## Space Trader for Windows 2.01 (2005–2008)
- **Jay French**: C# port. https://github.com/SpaceTraderGame/SpaceTrader-Windows
- **David Pierron**: additional coding.

## License
Parsec Merchant is free software under the **GNU General Public License, version 2 or (at your option) any later version**. See [LICENSE](LICENSE). The game rules, data tables and in-game texts are derived from the GPL sources above.

## Artwork
All artwork, icons and sounds in Parsec Merchant are new and generated in code. **None of the original Space Trader pictures are used.** They are © Alexander Lawrence and William W. Connors and are not covered by the GPL.

Provenance: every ship, portrait, planet, glyph, scene and icon picture is original and generated at run time by the ParsecArt code: SwiftUI shapes and Core Graphics for the vector art, and, since 1.1, planet maps baked from seeded noise and projected onto a sphere (on the CPU for stills, and by a Metal shader written in this repository for the live Bridge planet). There are no third-party assets, textures or shaders. The original Space Trader images were not opened, traced or used as references while designing the art. The only image files in the repository are the app icon PNGs, which are outputs of `scripts/make-icon.sh` (reproducible with `scripts/make-icon.sh --check`).

## Trademark
"Space Trader" is used here only to credit the original work. Parsec Merchant is not affiliated with HermitWorks Entertainment or any owner of that name.
