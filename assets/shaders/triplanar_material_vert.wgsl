#import bevy_pbr::mesh_functions as mesh_functions
#import bevy_pbr::view_transformations as view_transformations

struct Vertex {
    @builtin(instance_index) instance_index: u32,
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) material_weights: u32,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) world_position: vec4<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) material_weights: vec4<f32>,
    @location(3) @interpolate(flat) instance_index: u32,
};

// The builtin one didn't work in webgl.
// "'unpackUnorm4x8' : no matching overloaded function found"
// https://github.com/gfx-rs/naga/issues/2006
fn unpack_unorm4x8_(v: u32) -> vec4<f32> {
    return vec4(
        f32(v & 0xFFu),
        f32((v >> 8u) & 0xFFu),
        f32((v >> 16u) & 0xFFu),
        f32((v >> 24u) & 0xFFu)
    ) / 255.0;
}

@vertex
fn vertex(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;

    var model = mesh_functions::get_model_matrix(vertex.instance_index);

    out.world_normal = mesh_functions::mesh_normal_local_to_world(vertex.normal, vertex.instance_index);
    out.world_position = mesh_functions::mesh_position_local_to_world(
        model, vec4<f32>(vertex.position, 1.0)
    );
    out.clip_position = view_transformations::position_world_to_clip(out.world_position.xyz);
    out.material_weights = unpack_unorm4x8_(vertex.material_weights);
    out.instance_index = vertex.instance_index;

    return out;
}

