#define_import_path trimap::triplanar

fn sample_normal_map(
    two_component_normal_map: bool,
    flip_normal_map_y: bool,
    tex: texture_2d_array<f32>,
    samp: sampler,
    flags: u32,
    uv: vec2<f32>,
    layer: i32
) -> vec3<f32> {
    var Nt = textureSample(tex, samp, uv, layer).rgb;
    if (two_component_normal_map) {
        Nt = vec3<f32>(Nt.rg * 2.0 - 1.0, 0.0);
        Nt.z = sqrt(1.0 - Nt.x * Nt.x - Nt.y * Nt.y);
    } else {
        Nt = Nt * 2.0 - 1.0;
    }
    if (flip_normal_map_y) {
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
    two_component_normal_map: bool,
    flip_normal_map_y: bool,
    tex: texture_2d_array<f32>,
    samp: sampler,
    flags: u32,
    layer: i32,
    world_normal: vec3<f32>,
    tm: TriplanarMapping,
) -> vec3<f32> {
    // Tangent space normals.
    var tnormalx = sample_normal_map(two_component_normal_map, flip_normal_map_y, tex, samp, flags, tm.uv_x, layer);
    var tnormaly = sample_normal_map(two_component_normal_map, flip_normal_map_y, tex, samp, flags, tm.uv_y, layer);
    var tnormalz = sample_normal_map(two_component_normal_map, flip_normal_map_y, tex, samp, flags, tm.uv_z, layer);

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
    two_component_normal_map: bool,
    flip_normal_map_y: bool,
    tex: texture_2d_array<f32>,
    samp: sampler,
    flags: u32,
    w_mtl: vec4<f32>,
    world_normal: vec3<f32>,
    tm: TriplanarMapping,
) -> vec3<f32> {
    // Conditional sampling improves performance quite a bit.
    var sum = vec3(0.0);
    if (w_mtl.r > 0.0) {
        sum += w_mtl.r * triplanar_normal_to_world(
            two_component_normal_map, flip_normal_map_y, tex, samp, flags, 0, world_normal, tm
        );
    }
    if (w_mtl.g > 0.0) {
        sum += w_mtl.g * triplanar_normal_to_world(
            two_component_normal_map, flip_normal_map_y, tex, samp, flags, 1, world_normal, tm
        );
    }
    if (w_mtl.b > 0.0) {
        sum += w_mtl.b * triplanar_normal_to_world(
            two_component_normal_map, flip_normal_map_y, tex, samp, flags, 2, world_normal, tm
        );
    }
    if (w_mtl.a > 0.0) {
        sum += w_mtl.a * triplanar_normal_to_world(
            two_component_normal_map, flip_normal_map_y, tex, samp, flags, 3, world_normal, tm
        );
    }
    return normalize(sum);
}

