#import bevy_pbr::pbr_functions as pbr_functions
#import bevy_pbr::pbr_types as pbr_types

#import bevy_pbr::mesh_bindings::mesh
#import bevy_pbr::mesh_view_bindings::{view, fog, screen_space_ambient_occlusion_texture}
#import bevy_pbr::mesh_view_types::{FOG_MODE_OFF}
#import bevy_core_pipeline::tonemapping::{screen_space_dither, powsafe, tone_mapping}

#ifdef SCREEN_SPACE_AMBIENT_OCCLUSION
#import bevy_pbr::gtao_utils::gtao_multibounce
#endif

#import bevy_pbr::mesh_functions as mesh_functions
#import bevy_pbr::view_transformations as view_transformations

#import trimap::biplanar::{calculate_biplanar_mapping, biplanar_texture_splatted}
#import trimap::triplanar::{calculate_triplanar_mapping, triplanar_normal_to_world_splatted}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) world_position: vec4<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) material_weights: vec4<f32>,
    @location(3) @interpolate(flat) instance_index: u32,
};

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

fn alpha_discard_copy_paste(material: TriplanarMaterial, output_color: vec4<f32>) -> vec4<f32>{
    var color = output_color;
    if ((material.flags & pbr_types::STANDARD_MATERIAL_FLAGS_ALPHA_MODE_OPAQUE) != 0u) {
        // NOTE: If rendering as opaque, alpha should be ignored so set to 1.0
        color.a = 1.0;
    } else if ((material.flags & pbr_types::STANDARD_MATERIAL_FLAGS_ALPHA_MODE_MASK) != 0u) {
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

@fragment
fn fragment(
    in: VertexOutput,
    @builtin(front_facing) is_front: bool,
) -> @location(0) vec4<f32> {
    var output_color: vec4<f32> = material.base_color;

    let is_orthographic = view.projection[3].w == 1.0;
    let V = pbr_functions::calculate_view(in.world_position, is_orthographic);

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

    if ((material.flags & pbr_types::STANDARD_MATERIAL_FLAGS_BASE_COLOR_TEXTURE_BIT) != 0u) {
        output_color *= biplanar_texture_splatted(
            base_color_texture,
            base_color_sampler,
            in.material_weights,
            bimap
        );
    }

    // NOTE: Unlit bit not set means == 0 is true, so the true case is if lit
    if ((material.flags & pbr_types::STANDARD_MATERIAL_FLAGS_UNLIT_BIT) == 0u) {
        // Prepare a 'processed' StandardMaterial by sampling all textures to resolve
        // the material members
        var pbr_input: pbr_types::PbrInput;

        pbr_input.material.base_color = output_color;
        pbr_input.material.reflectance = material.reflectance;
        pbr_input.material.flags = material.flags;
        pbr_input.material.alpha_cutoff = material.alpha_cutoff;

        // TODO use .a for exposure compensation in HDR
        var emissive: vec4<f32> = material.emissive;
        if ((material.flags & pbr_types::STANDARD_MATERIAL_FLAGS_EMISSIVE_TEXTURE_BIT) != 0u) {
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
        if ((material.flags & pbr_types::STANDARD_MATERIAL_FLAGS_METALLIC_ROUGHNESS_TEXTURE_BIT) != 0u) {
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

        // TODO: Split into diffuse/specular occlusion?
        var occlusion: vec3<f32> = vec3(1.0);
        if ((material.flags & pbr_types::STANDARD_MATERIAL_FLAGS_OCCLUSION_TEXTURE_BIT) != 0u) {
            occlusion = vec3(biplanar_texture_splatted(
                occlusion_texture,
                occlusion_sampler,
                in.material_weights,
                bimap
            ).r);
        }
#ifdef SCREEN_SPACE_AMBIENT_OCCLUSION
        let ssao = textureLoad(screen_space_ambient_occlusion_texture, vec2<i32>(in.clip_position.xy), 0i).r;
        let ssao_multibounce = gtao_multibounce(ssao, pbr_input.material.base_color.rgb);
        occlusion = min(occlusion, ssao_multibounce);
#endif
        pbr_input.occlusion = occlusion;

        pbr_input.frag_coord = in.clip_position;
        pbr_input.world_position = in.world_position;

        pbr_input.world_normal = pbr_functions::prepare_world_normal(
            in.world_normal,
            (material.flags & pbr_types::STANDARD_MATERIAL_FLAGS_DOUBLE_SIDED_BIT) != 0u,
            is_front,
        );

        pbr_input.is_orthographic = is_orthographic;


        pbr_input.N = triplanar_normal_to_world_splatted(
            (material.flags & pbr_types::STANDARD_MATERIAL_FLAGS_TWO_COMPONENT_NORMAL_MAP) != 0u,
            (material.flags & pbr_types::STANDARD_MATERIAL_FLAGS_FLIP_NORMAL_MAP_Y) != 0u,
            normal_map_texture,
            normal_map_sampler,
            material.flags,
            in.material_weights,
            in.world_normal,
            trimap,
        );
        pbr_input.V = V;
        pbr_input.occlusion = occlusion;

        pbr_input.flags = mesh[in.instance_index].flags;

        output_color = pbr_functions::apply_pbr_lighting(pbr_input);
    } else {
        output_color = alpha_discard_copy_paste(material, output_color);
    }

    // fog
    if (fog.mode != FOG_MODE_OFF && (material.flags & pbr_types::STANDARD_MATERIAL_FLAGS_FOG_ENABLED_BIT) != 0u) {
        output_color = pbr_functions::apply_fog(fog, output_color, in.world_position.xyz, view.world_position.xyz);
    }

#ifdef TONEMAP_IN_SHADER
    output_color = tone_mapping(output_color, view.color_grading);
#ifdef DEBAND_DITHER
    var output_rgb = output_color.rgb;
    output_rgb = powsafe(output_rgb, 1.0 / 2.2);
    output_rgb = output_rgb + screen_space_dither(in.clip_position.xy);
    // This conversion back to linear space is required because our output texture format is
    // SRGB; the GPU will assume our output is linear and will apply an SRGB conversion.
    output_rgb = powsafe(output_rgb, 2.2);
    output_color = vec4(output_rgb, output_color.a);
#endif
#endif
#ifdef PREMULTIPLY_ALPHA
    output_color = pbr_functions::premultiply_alpha(material.flags, output_color);
#endif
    return output_color;
}

