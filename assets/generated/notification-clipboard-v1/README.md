# Notification clipboard sprites

Created with the built-in image generation tool for the notifications UI. The
game overlays live text and controls; no player-facing copy is baked into these
sprites.

| Sprite | Generation prompt summary |
| --- | --- |
| `clipboard.png` | Front-facing, painterly 2D clipboard; brown fiberboard, blank ivory ruled sheet, silver clip, transparent outside; no text or controls. |
| `clipboard-wide.png` | Matching ultrawide landscape phone variant with the same materials and open paper area; transparent outside; no text or controls. |
| `page-turn.png` | Four equal horizontal frames of a blank ruled paper sheet curling from its lower-right corner; transparent outside each frame. |

The live page-turn animation places the sprite at the lower-right edge of the
clipboard paper. Its top and left edges are faded at draw time to blend into the
base paper sprite.

Notification handwriting uses `assets/fonts/PatrickHand-Regular.ttf`. See
`assets/fonts/PatrickHand-LICENSE.txt` for its SIL Open Font License.
