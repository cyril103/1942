# Raid landscape, version 2

Created for Pacific Strike on 2026-10-07 with the built-in ImageGen tool. No third-party photograph or downloaded texture was used. The game's `islands-atlas.png` was supplied as the visual style reference.

`tropical-battlefield.png` (887 × 1774) is an authored overhead landscape, not a repeating material swatch. It is mapped once over the coastal terrain. Real targets, runway markings, terrain relief, shadows and vegetation instances are rendered separately by Godot. Fine soil detail uses the new original `coral-grass-detail.png` at low strength. Both files are the native ImageGen output, without resampling.

## Landscape prompt

```text
Use case: stylized-concept
Asset type: production color/albedo macro texture for a lush tropical Pacific island battlefield in a premium 3D vertically scrolling shoot-em-up game.
Reference image: existing game island atlas; borrow exactly its detailed tropical vegetation, vivid but natural emerald greens, coral sand, geological rock shapes and beautifully rich game-art finish, but create ONE new continuous land texture, not an atlas.
Create a tall vertical 1536 by 3072 texture, absolutely orthographic overhead, camera pointing straight down. Every pixel is viewed from directly above with no horizon, no isometric perspective, no labels or UI. Fill the entire rectangular image with terrain; this is an interior terrain texture, NOT a cutout island, NO ocean or water within the image, NO border or frame.
Composition: the middle 65 percent of width is a broad irregular open grass airfield clearing, many connected lush emerald and sun-warmed green meadows, sandy coral dirt tracks and pale sandy clearings with subtle tire ruts, exposed stony ground, tiny scattered tufts of jungle grass and tiny plants, drainage ditches and beautiful fine natural texture everywhere. Along the far left and right 15 percent edges, lush dense varied tropical jungle canopy, coconut palms, broadleaf trees, ferns, large weathered pale granite outcrops and dark rich ground vegetation. Jungle also grows in scattered small natural groves near the sides, leaving the central area predominantly open. Compose different areas all along the vertical extent to give a long unfolding landscape, no repetition.
Center-right there is an open uninterrupted north-south grass clearing where a separate real 3D runway will be laid by the engine; do NOT paint any runway. Tracks should meander primarily in the left and center clearing. Terrain scale: image spans about 60 by 150 meters, tree crowns roughly 3 to 5 meters across, grass/dirt detail physically fine. Natural terrain first, elegantly composed, strong depth in the peripheral trees.
Lighting: tropical daytime, natural soft sun from upper-left, minimal long shadows; rich microcontrast, not gray, not murky, not brown military camouflage, not neon or fluorescent. Use the reference's rich natural greens and warm white coral-sand brightness. Extremely detailed hand-crafted realistic game texture feel, excellent material definition of grass, dirt, stone, leaves, organic irregular shapes. No military buildings, no vehicles, no aircraft, no people, no guns, no bomb craters, no text, no symbols, no watermarks.
```

## Fine material prompt

```text
Use case: stylized-concept
Asset type: seamless microdetail ground albedo texture for close aerial 3D tropical Pacific battlefield.
Generate one extremely detailed 2048 by 2048 square texture of lush short tropical grass and coral sandy soil, straight-down orthographic macro aerial view. Each edge must tile seamlessly. No large features, no trees, no canopy, no roads or buildings. Realistic tiny sharp grass blades, intricate clusters of creeping tropical plants, darker rich moist earthy gaps, small pale coral pebbles, tiny warm sand flecks, natural organic grass coverage 80 percent and tan sandy soil gaps 20 percent. Scale entire image is approximately 3 meters by 3 meters. Premium game environmental material with rich realistic medium and deep emerald/olive greens, lively sun-warmed grass highlights, and warm coral beige mineral soil. Avoid big smooth patches, big stains, yellow fluorescent grass, faded desaturated grey-brown, cartoon patterns, blurry details, text, shadows cast by offscreen objects, water, objects or border. Flat neutral diffuse daylight appropriate for PBR albedo, refined high-frequency detail throughout, visually continuous and naturally mottled; no strong directional shadows or lighting gradient.
```
