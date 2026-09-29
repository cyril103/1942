# UI concept proposals

Five visual mockups generated with the built-in image generation tool from renders/combat-02.png. These are art-direction proposals, not captures of implemented UI. Score, high score, lives and radar values are illustrative.

1. 01-arcade-heritage.png: navy, ivory pixel typography, amber and red arcade accents.
2. 02-cockpit.png: dark enamel, rivets and amber instrument displays.
3. 03-neon.png: cyan and magenta vector arcade style.
4. 04-naval.png: petroleum blue, cartographic lines and restrained orange.
5. 05-bezel.png: screenprinted navy, cream and terracotta arcade side art.

Target implementation: full-height portrait 3:4 gameplay within a 16:9 screen. At 1920x1080, gameplay is 810x1080, with 555-pixel side panels. Generated mockups approximate these proportions and are not pixel-exact layout specifications; enforce the exact aspect ratio in Godot when implementing the selected direction. No game code changed for this exploration.

Initial prompts: prompts.json. Layout correction pass: correction-prompt.txt.
