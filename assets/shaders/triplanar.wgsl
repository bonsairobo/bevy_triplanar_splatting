#import bevy_pbr::mesh_view_bindings
#import bevy_pbr::mesh_types

@group(2) @binding(0)
var<uniform> mesh: Mesh;

#import bevy_pbr::mesh_functions

struct Vertex {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) material_weights: u32,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) world_position: vec4<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) material_weights: vec4<f32>,
};

@vertex
fn vertex(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;

    var model = mesh.model;
    out.world_normal = mesh_normal_local_to_world(vertex.normal);
    out.world_position = mesh_position_local_to_world(model, vec4<f32>(vertex.position, 1.0));
    out.clip_position = mesh_position_world_to_clip(out.world_position);
    out.material_weights = vec4(
        f32(vertex.material_weights & 0xFFu),
        f32((vertex.material_weights >> 8u) & 0xFFu),
        f32((vertex.material_weights >> 16u) & 0xFFu),
        f32((vertex.material_weights >> 24u) & 0xFFu)
    );
    // Weights should add up to 1.
    out.material_weights /= (
        out.material_weights.x +
        out.material_weights.y +
        out.material_weights.z +
        out.material_weights.w
    );

    return out;
}

#import bevy_pbr::utils
#import bevy_pbr::clustered_forward
#import bevy_pbr::lighting
#import bevy_pbr::shadows
#import bevy_pbr::pbr_types
#import bevy_pbr::pbr_functions

struct TriplanarMaterial {
    base_color: vec4<f32>,
    emissive: vec4<f32>,
    perceptual_roughness: f32,
    metallic: f32,
    reflectance: f32,
    flags: u32,
    alpha_cutoff: f32,
    uv_scale: f32,
};

@group(1) @binding(0)
var<uniform> material: TriplanarMaterial;
@group(1) @binding(1)
var base_color_texture: texture_2d_array<f32>;
@group(1) @binding(2)
var base_color_sampler: sampler;
@group(1) @binding(3)
var emissive_texture: texture_2d_array<f32>;
@group(1) @binding(4)
var emissive_sampler: sampler;
@group(1) @binding(5)
var metallic_roughness_texture: texture_2d_array<f32>;
@group(1) @binding(6)
var metallic_roughness_sampler: sampler;
@group(1) @binding(7)
var occlusion_texture: texture_2d_array<f32>;
@group(1) @binding(8)
var occlusion_sampler: sampler;
@group(1) @binding(9)
var normal_map_texture: texture_2d_array<f32>;
@group(1) @binding(10)
var normal_map_sampler: sampler;

// HACK: this is copied from bevy's pbr_functions.wgsl because we have a
// different input material type
fn alpha_discard_copy_paste(material: TriplanarMaterial, output_color: vec4<f32>) -> vec4<f32>{
    var color = output_color;
    if ((material.flags & STANDARD_MATERIAL_FLAGS_ALPHA_MODE_OPAQUE) != 0u) {
        // NOTE: If rendering as opaque, alpha should be ignored so set to 1.0
        color.a = 1.0;
    } else if ((material.flags & STANDARD_MATERIAL_FLAGS_ALPHA_MODE_MASK) != 0u) {
        if (color.a >= material.alpha_cutoff) {
            // NOTE: If rendering as masked alpha and >= the cutoff, render as fully opaque
            color.a = 1.0;
        } else {
            // NOTE: output_color.a < in.material.alpha_cutoff should not is not rendered
            // NOTE: This and any other discards mean that early-z testing cannot be done!
            discard;
        }
    }
    return color;
}

fn sample_normal_map(flags: u32, uv: vec2<f32>, layer: i32) -> vec3<f32> {
    var Nt = textureSample(normal_map_texture, normal_map_sampler, uv, layer).rgb;
    if ((flags & STANDARD_MATERIAL_FLAGS_TWO_COMPONENT_NORMAL_MAP) != 0u) {
        Nt = vec3<f32>(Nt.rg * 2.0 - 1.0, 0.0);
        Nt.z = sqrt(1.0 - Nt.x * Nt.x - Nt.y * Nt.y);
    } else {
        Nt = Nt * 2.0 - 1.0;
    }
    if ((flags & STANDARD_MATERIAL_FLAGS_FLIP_NORMAL_MAP_Y) != 0u) {
        Nt.y = -Nt.y;
    }
    return normalize(Nt);
}

struct TriplanarMapping {
    // weights for blending between the planes
    w: vec3<f32>,

    uv_x: vec2<f32>,
    uv_y: vec2<f32>,
    uv_z: vec2<f32>,
};

fn calculate_triplanar_mapping(p: vec3<f32>, n: vec3<f32>, k: f32) -> TriplanarMapping {
    var w = pow(abs(n), vec3(k));
    w = w / (w.x + w.y + w.z);
    return TriplanarMapping(w, p.yz, p.zx, p.xy);
}

fn triplanar_normal_to_world(
    flags: u32,
    layer: i32,
    world_normal: vec3<f32>,
    tm: TriplanarMapping,
) -> vec3<f32> {
    // Tangent space normals.
    var tnormalx = sample_normal_map(flags, tm.uv_x, layer);
    var tnormaly = sample_normal_map(flags, tm.uv_y, layer);
    var tnormalz = sample_normal_map(flags, tm.uv_z, layer);

    // Whiteout blend
    // https://bgolus.medium.com/normal-mapping-for-a-triplanar-shader-10bf39dca05a#ce80
    //
    // Swizzles are adapted to be compatible with biplanar mapping.
    tnormalx = vec3(tnormalx.xy + world_normal.yz, abs(tnormalx.z) * world_normal.x);
    tnormaly = vec3(tnormaly.xy + world_normal.zx, abs(tnormaly.z) * world_normal.y);
    tnormalz = vec3(tnormalz.xy + world_normal.xy, abs(tnormalz.z) * world_normal.z);

    // Swizzle tangent normals to match world orientation and triblend
    return normalize(
        tnormalx.zxy * tm.w.x +
        tnormaly.yzx * tm.w.y +
        tnormalz.xyz * tm.w.z
    );
}

fn triplanar_normal_to_world_splatted(
    flags: u32,
    w_mtl: vec4<f32>,
    world_normal: vec3<f32>,
    tm: TriplanarMapping,
) -> vec3<f32> {
    // Conditional sampling improves performance quite a bit.
    var sum = vec3(0.0);
    if (w_mtl.r > 0.0) {
        sum += w_mtl.r * triplanar_normal_to_world(flags, 0, world_normal, tm);
    }
    if (w_mtl.g > 0.0) {
        sum += w_mtl.g * triplanar_normal_to_world(flags, 1, world_normal, tm);
    }
    if (w_mtl.b > 0.0) {
        sum += w_mtl.b * triplanar_normal_to_world(flags, 2, world_normal, tm);
    }
    if (w_mtl.a > 0.0) {
        sum += w_mtl.a * triplanar_normal_to_world(flags, 3, world_normal, tm);
    }
    return normalize(sum);
}

struct BiplanarMapping {
    // weights for blending between the planes
    w: vec2<f32>,

    // major axis
    ma: i32,
    ma_uv: vec2<f32>,
    ma_dpdx: vec2<f32>,
    ma_dpdy: vec2<f32>,

    // median axis
    me: i32,
    me_uv: vec2<f32>,
    me_dpdx: vec2<f32>,
    me_dpdy: vec2<f32>,
};

// Do biplanar mapping: https://iquilezles.org/articles/biplanar/
// "p" point being textured
// "n" surface normal at "p"
// "k" controls the sharpness of the blending in the transitions areas
fn calculate_biplanar_mapping(p: vec3<f32>, n: vec3<f32>, k: f32) -> BiplanarMapping {
    // grab coord derivatives for texturing
    let dpdx = dpdx(p);
    let dpdy = dpdy(p);
    let n = abs(n);

    // NOTE: the axis permutations below are determined to be compatible with
    // the UVs from calculate_triplanar_mapping.

    // determine major axis (in x; yz are following axis)
    let ma = select(
        select(
            vec3(2, 0, 1),
            vec3(1, 2, 0),
            n.y > n.z,
        ),
        vec3(0, 1, 2),
        n.x > n.y && n.x > n.z
    );

    // determine minor axis (in x; yz are following axis)
    let mi = select(
        select(
            vec3(2, 0, 1),
            vec3(1, 2, 0),
            n.y < n.z,
        ),
        vec3(0, 1, 2),
        n.x < n.y && n.x < n.z
    );

    // determine median axis (in x; yz are following axis)
    let me = vec3(3) - mi - ma;

    // project
    let ma_uv   = vec2(   p[ma.y],    p[ma.z]);
    let ma_dpdx = vec2(dpdx[ma.y], dpdx[ma.z]);
    let ma_dpdy = vec2(dpdy[ma.y], dpdy[ma.z]);
    let me_uv   = vec2(   p[me.y],    p[me.z]);
    let me_dpdx = vec2(dpdx[me.y], dpdx[me.z]);
    let me_dpdy = vec2(dpdy[me.y], dpdy[me.z]);

    // blend factors
    var w = vec2(n[ma.x], n[me.x]);

    // make local support (optional)
    //
    // NOTE: Inigo says (https://iquilezles.org/articles/biplanar/):
    //
    // > If [this line] wasn't implemented, we'd have some (often small) texture
    // > discontinuities. These discontinuities would naturally happen in areas
    // > where the normal points in one of the eight (±1,±1,±1) directions. This
    // > happens because at some point the minor and median projection
    // > directions will switch places and one projection will be replaced by
    // > another one. In practice with most textures and with most blending
    // > shaping coefficients "l", the discontinuity is difficult to see, if at
    // > all, but the discontinuity is always there. Luckily it's easy to get
    // > rid of it by remapping the weights such that 1/sqrt(3), 0.5773, is
    // > mapped to zero.
    //
    // I fudge the value a little to avoid more artifacts.
    // let remap = 0.5773;
    let remap = 0.57;
    w = clamp((w - remap) / (1.0 - remap), vec2(0.0), vec2(1.0));

    // shape transition
    w = pow(w, vec2(k / 8.0));
    // normalize
    w = w / (w.x + w.y);

    return BiplanarMapping(
        w,
        ma.x, ma_uv, ma_dpdx, ma_dpdy,
        me.x, me_uv, me_dpdx, me_dpdy
    );
}

fn biplanar_texture(
    tex: texture_2d_array<f32>,
    samp: sampler,
    layer: i32,
    bm: BiplanarMapping
) -> vec4<f32> {
    let x = textureSampleGrad(tex, samp, bm.ma_uv, layer, bm.ma_dpdx, bm.ma_dpdy);
    let y = textureSampleGrad(tex, samp, bm.me_uv, layer, bm.me_dpdx, bm.me_dpdy);
    return bm.w.x * x + bm.w.y * y;
}

fn biplanar_texture_splatted(
    tex: texture_2d_array<f32>,
    samp: sampler,
    w_mtl: vec4<f32>,
    bimap: BiplanarMapping
) -> vec4<f32> {
    // Conditional sampling improves performance quite a bit.
    var sum = vec4(0.0);
    if (w_mtl.r > 0.0) {
        sum += w_mtl.r * biplanar_texture(tex, samp, 0, bimap);
    }
    if (w_mtl.g > 0.0) {
        sum += w_mtl.g * biplanar_texture(tex, samp, 1, bimap);
    }
    if (w_mtl.b > 0.0) {
        sum += w_mtl.b * biplanar_texture(tex, samp, 2, bimap);
    }
    if (w_mtl.a > 0.0) {
        sum += w_mtl.a * biplanar_texture(tex, samp, 3, bimap);
    }
    return sum;
}

struct FragmentInput {
    @builtin(front_facing) is_front: bool,
    @builtin(position) frag_coord: vec4<f32>,
    @location(0) world_position: vec4<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) material_weights: vec4<f32>,
};

@fragment
fn fragment(in: FragmentInput) -> @location(0) vec4<f32> {
    var output_color: vec4<f32> = material.base_color;

    var bimap = calculate_biplanar_mapping(in.world_position.xyz, in.world_normal, 8.0);
    bimap.ma_uv *= material.uv_scale;
    bimap.me_uv *= material.uv_scale;
    // Triplanar is only used for normal mapping because the transitions between
    // planar projections look significantly better when there is high contrast
    // in lighting direction.
    var trimap = calculate_triplanar_mapping(in.world_position.xyz, in.world_normal, 8.0);
    trimap.uv_x *= material.uv_scale;
    trimap.uv_y *= material.uv_scale;
    trimap.uv_z *= material.uv_scale;

    if ((material.flags & STANDARD_MATERIAL_FLAGS_BASE_COLOR_TEXTURE_BIT) != 0u) {
        output_color *= biplanar_texture_splatted(
            base_color_texture,
            base_color_sampler,
            in.material_weights,
            bimap
        );
    }

    if ((material.flags & STANDARD_MATERIAL_FLAGS_UNLIT_BIT) == 0u) {
        var pbr_input: PbrInput;

        pbr_input.material.base_color = output_color;
        pbr_input.material.reflectance = material.reflectance;
        pbr_input.material.flags = material.flags;
        pbr_input.material.alpha_cutoff = material.alpha_cutoff;

        // TODO use .a for exposure compensation in HDR
        var emissive: vec4<f32> = material.emissive;
        if ((material.flags & STANDARD_MATERIAL_FLAGS_EMISSIVE_TEXTURE_BIT) != 0u) {
            let biplanar_emissive = biplanar_texture_splatted(
                emissive_texture,
                emissive_sampler,
                in.material_weights,
                bimap
            ).rgb;
            emissive = vec4<f32>(emissive.rgb * biplanar_emissive, 1.0);
        }
        pbr_input.material.emissive = emissive;

        var metallic: f32 = material.metallic;
        var perceptual_roughness: f32 = material.perceptual_roughness;
        if ((material.flags & STANDARD_MATERIAL_FLAGS_METALLIC_ROUGHNESS_TEXTURE_BIT) != 0u) {
            let metallic_roughness = biplanar_texture_splatted(
                metallic_roughness_texture,
                metallic_roughness_sampler,
                in.material_weights,
                bimap
            );
            // Sampling from GLTF standard channels for now
            metallic = metallic * metallic_roughness.b;
            perceptual_roughness = perceptual_roughness * metallic_roughness.g;
        }
        pbr_input.material.metallic = metallic;
        pbr_input.material.perceptual_roughness = perceptual_roughness;

        var occlusion: f32 = 1.0;
        if ((material.flags & STANDARD_MATERIAL_FLAGS_OCCLUSION_TEXTURE_BIT) != 0u) {
            occlusion = biplanar_texture_splatted(
                occlusion_texture,
                occlusion_sampler,
                in.material_weights,
                bimap
            ).r;
        }
        pbr_input.occlusion = occlusion;

        pbr_input.frag_coord = in.frag_coord;
        pbr_input.world_position = in.world_position;
        pbr_input.world_normal = prepare_world_normal(
            in.world_normal,
            (material.flags & STANDARD_MATERIAL_FLAGS_DOUBLE_SIDED_BIT) != 0u,
            in.is_front,
        );

        pbr_input.is_orthographic = view.projection[3].w == 1.0;

        pbr_input.N = triplanar_normal_to_world_splatted(
            material.flags,
            in.material_weights,
            in.world_normal,
            trimap,
        );
        pbr_input.V = calculate_view(in.world_position, pbr_input.is_orthographic);
        output_color = pbr(pbr_input);
    } else {
        output_color = alpha_discard_copy_paste(material, output_color);
    }

#ifdef TONEMAP_IN_SHADER
    output_color = tone_mapping(output_color);
#endif
#ifdef DEBAND_DITHER
    var output_rgb = output_color.rgb;
    output_rgb = pow(output_rgb, vec3<f32>(1.0 / 2.2));
    output_rgb = output_rgb + screen_space_dither(in.frag_coord.xy);
    // This conversion back to linear space is required because our output
    // texture format is SRGB; the GPU will assume our output is linear and will
    // apply an SRGB conversion.
    output_rgb = pow(output_rgb, vec3<f32>(2.2));
    output_color = vec4(output_rgb, output_color.a);
#endif

    return output_color;
}
