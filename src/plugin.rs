use crate::triplanar_material::TriplanarMaterial;
use bevy::asset::load_internal_asset;
use bevy::prelude::*;
use bevy::reflect::TypeUuid;

const TRIPLANAR_SHADER_HANDLE: HandleUntyped =
    HandleUntyped::weak_from_u64(Shader::TYPE_UUID, 2631398565563939187);
const BIPLANAR_SHADER_HANDLE: HandleUntyped =
    HandleUntyped::weak_from_u64(Shader::TYPE_UUID, 1945949403120376729);

pub struct TriplanarMaterialPlugin;

impl Plugin for TriplanarMaterialPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(MaterialPlugin::<TriplanarMaterial>::default());

        load_internal_asset!(
            app,
            TRIPLANAR_SHADER_HANDLE,
            "shaders/triplanar.wgsl",
            Shader::from_wgsl
        );
        load_internal_asset!(
            app,
            BIPLANAR_SHADER_HANDLE,
            "shaders/biplanar.wgsl",
            Shader::from_wgsl
        );
    }
}
