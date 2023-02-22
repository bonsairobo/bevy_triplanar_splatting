use bevy::{
    // pbr::wireframe::{WireframeConfig, WireframePlugin},
    prelude::*,
    render::{
        render_resource::{AddressMode, FilterMode, SamplerDescriptor},
        texture::{CompressedImageFormats, ImageSampler},
    },
};
use bevy_triplanar_splatting::triplanar_material::{TriplanarMaterial, ATTRIBUTE_MATERIAL_WEIGHTS};
use smooth_bevy_cameras::{controllers::fps::*, LookTransformPlugin};

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_asset_loader(
            bevy_triplanar_splatting::basis_linear_loader::BasisLinearLoader {
                supported_compressed_formats: CompressedImageFormats::BC, // NVIDIA
            },
        )
        .add_plugin(MaterialPlugin::<TriplanarMaterial>::default())
        // .add_plugin(WireframePlugin::default())
        .add_plugin(LookTransformPlugin)
        .add_plugin(FpsCameraPlugin::default())
        .add_startup_system(setup)
        .add_system(spawn_meshes)
        .add_system(move_lights)
        .run();
}

/// set up a simple 3D scene
fn setup(
    asset_server: Res<AssetServer>,
    mut commands: Commands,
    // mut wireframe_config: ResMut<WireframeConfig>,
) {
    // wireframe_config.global = true;

    // start loading materials
    commands.insert_resource(MaterialHandles {
        base_color: LoadingImage::new(asset_server.load("array_material/albedo.basis")),
        occlusion: LoadingImage::new(asset_server.load("array_material/ao.basis")),
        normal_map: LoadingImage::new(asset_server.load("array_material/normal.basis_linear")),
        metal_rough: LoadingImage::new(asset_server.load("array_material/metal_rough.basis")),
        // TODO: support fallback image
        emissive: LoadingImage::new(asset_server.load("array_material/albedo.basis")),
        spawned: false,
    });

    // commands.insert_resource(AmbientLight {
    //     brightness: 2.0,
    //     ..default()
    // });

    // Spawn lights and camera.
    commands.spawn((
        MovingLight,
        PointLightBundle {
            point_light: PointLight {
                intensity: 50000.,
                range: 100.,
                ..default()
            },
            ..default()
        },
    ));

    commands
        .spawn(Camera3dBundle::default())
        .insert(FpsCameraBundle::new(
            FpsCameraController {
                translate_sensitivity: 8.0,
                ..Default::default()
            },
            Vec3::new(12.0, 12.0, 12.0),
            Vec3::new(0., 0., 0.),
        ));
}

#[derive(Component)]
struct MovingLight;

fn move_lights(time: Res<Time>, mut lights: Query<(&MovingLight, &mut Transform)>) {
    let t = time.elapsed_seconds();
    for (_, mut tfm) in lights.iter_mut() {
        tfm.translation = 15.0 * Vec3::new(t.cos(), 1.0, t.sin());
    }
}

#[derive(Resource)]
struct MaterialHandles {
    base_color: LoadingImage,
    occlusion: LoadingImage,
    normal_map: LoadingImage,
    metal_rough: LoadingImage,
    emissive: LoadingImage,
    spawned: bool,
}

impl MaterialHandles {
    fn all_loaded(&self) -> bool {
        self.base_color.loaded
            && self.occlusion.loaded
            && self.normal_map.loaded
            && self.metal_rough.loaded
            && self.emissive.loaded
    }

    fn check_loaded(&mut self, created_handle: &Handle<Image>) -> bool {
        // Check every handle without short circuiting because they might be
        // duplicates.
        let mut any_loaded = false;
        any_loaded |= self.base_color.check_loaded(created_handle);
        any_loaded |= self.occlusion.check_loaded(created_handle);
        any_loaded |= self.normal_map.check_loaded(created_handle);
        any_loaded |= self.metal_rough.check_loaded(created_handle);
        any_loaded |= self.emissive.check_loaded(created_handle);
        any_loaded
    }
}

struct LoadingImage {
    handle: Handle<Image>,
    loaded: bool,
}

impl LoadingImage {
    fn new(handle: Handle<Image>) -> Self {
        Self {
            handle,
            loaded: false,
        }
    }

    fn check_loaded(&mut self, created_handle: &Handle<Image>) -> bool {
        if *created_handle == self.handle {
            self.loaded = true;
            true
        } else {
            false
        }
    }
}

fn spawn_meshes(
    mut asset_events: EventReader<AssetEvent<Image>>,
    mut assets: ResMut<Assets<Image>>,
    mut commands: Commands,
    mut handles: ResMut<MaterialHandles>,
    mut materials: ResMut<Assets<TriplanarMaterial>>,
    mut meshes: ResMut<Assets<Mesh>>,
) {
    if handles.spawned {
        return;
    }

    for event in asset_events.iter() {
        if let AssetEvent::Created { handle } = event {
            if handles.check_loaded(handle) {
                let texture = assets.get_mut(handle).unwrap();
                texture.sampler_descriptor = ImageSampler::Descriptor(SamplerDescriptor {
                    address_mode_u: AddressMode::Repeat,
                    address_mode_v: AddressMode::Repeat,
                    address_mode_w: AddressMode::Repeat,
                    min_filter: FilterMode::Linear,
                    mag_filter: FilterMode::Linear,
                    mipmap_filter: FilterMode::Linear,
                    ..default()
                });
            }
        }
    }

    if !handles.all_loaded() {
        return;
    }
    handles.spawned = true;

    let mut sphere_mesh = Mesh::try_from(shape::Icosphere {
        radius: 5.0,
        subdivisions: 6,
    })
    .unwrap();

    let material_weights: Vec<u32> = sphere_mesh
        .attribute(Mesh::ATTRIBUTE_NORMAL)
        .unwrap()
        .as_float3()
        .unwrap()
        .iter()
        .map(|p| {
            let p = Vec3::from(*p);
            let w = sigmoid(signed_weight_to_unsigned(p.dot(Vec3::X)), 10.0);
            let w0 = (w * 255.0).clamp(0.0, 255.0) as u32;
            let w1 = 255 - w0;
            encode_weights([w0, 0, w1, 0])
            // encode_weights([255, 0, 0, 0])
        })
        .collect();
    sphere_mesh.insert_attribute(ATTRIBUTE_MATERIAL_WEIGHTS, material_weights);

    commands.spawn(MaterialMeshBundle {
        mesh: meshes.add(sphere_mesh),
        material: materials.add(TriplanarMaterial {
            metallic: 0.05,
            perceptual_roughness: 0.9,

            base_color_texture: Some(handles.base_color.handle.clone()),
            emissive_texture: Some(handles.emissive.handle.clone()),
            metallic_roughness_texture: Some(handles.metal_rough.handle.clone()),
            normal_map_texture: Some(handles.normal_map.handle.clone()),
            occlusion_texture: Some(handles.occlusion.handle.clone()),

            uv_scale: 1.0,
            ..default()
        }),
        ..default()
    });
}

/// Linear transformation from domain `[-1.0, 1.0]` into range `[0.0, 1.0]`.
fn signed_weight_to_unsigned(x: f32) -> f32 {
    0.5 * (x + 1.0)
}

fn encode_weights(w: [u32; 4]) -> u32 {
    w[0] | (w[1] << 8) | (w[2] << 16) | (w[3] << 24)
}

fn sigmoid(x: f32, beta: f32) -> f32 {
    1.0 / (1.0 + (x / (1.0 - x)).powf(-beta))
}
