# bevy_triplanar_splatting

Triplanar Mapping and Material Blending (AKA Splatting) for Bevy Engine

![Screenshot](https://media.githubusercontent.com/media/bonsairobo/bevy_triplanar_splatting/main/examples/screen.png)

## Scope

This crate provides the
[`TriplanarMaterial`](triplanar_material::TriplanarMaterial), which is based
on `bevy_pbr`'s [`StandardMaterial`](bevy::pbr::StandardMaterial), but it
supports blending up to 4 materials using array textures and a new
[`ATTRIBUTE_MATERIAL_WEIGHTS`](triplanar_material::ATTRIBUTE_MATERIAL_WEIGHTS)
vertex attribute.

## Implementation

The triplanar material is implemented using the
[`AsBindGroup`](bevy::render::render_resource::AsBindGroup) derive macro and
the [`Material`](bevy::pbr::Material) trait. Most of the magic happens in
the shader code.

Where possible, we reuse shader imports from [`bevy::pbr`](bevy::pbr) to
implement lighting effects. Sadly there are still some shader functions and
code blocks that are copy-pasted from Bevy; we are hoping to eliminate these
in the future to make this crate easier to maintain.

The new shader code is mostly concerned with how array textures are sampled
and blended together. The techniques therein were sourced from the following
references:

- Ben Golus, ["Normal Mapping for a Triplanar
  Shader"](https://bgolus.medium.com/normal-mapping-for-a-triplanar-shader-10bf39dca05a)
- Inigo Quilez, ["Biplanar
  Mapping"](https://iquilezles.org/articles/biplanar/)
- Colin Barré-Brisebois and Stephen Hill, ["Blending in
  Detail"](https://blog.selfshadow.com/publications/blending-in-detail/)

## Road Map

- [ ] fix bevy issue (#6920) with `FallbackImage` (for array textures)
- [ ] per-layer uniform constants (e.g. "emissive", "metallic", etc.)
- [ ] support different texture per plane, using more layers
- [ ] blend materials using depth/height map
  - see ["Advanced Terrain Texture
    Splatting"](https://www.gamedeveloper.com/programming/advanced-terrain-texture-splatting)
