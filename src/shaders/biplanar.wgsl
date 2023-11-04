#define_import_path trimap::biplanar

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
fn calculate_biplanar_mapping(p: vec3<f32>, n_in: vec3<f32>, k: f32) -> BiplanarMapping {
    // grab coord derivatives for texturing
    let dpdx = dpdx(p);
    let dpdy = dpdy(p);
    let n = abs(n_in);

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
