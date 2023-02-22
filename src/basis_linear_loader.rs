use bevy::asset::{AssetLoader, Error, LoadContext, LoadedAsset};
use bevy::render::texture::{CompressedImageFormats, Image, ImageType};
use bevy::utils::BoxedFuture;

// TODO: remove when https://github.com/bevyengine/bevy/issues/6371 is resolved
//
/// Loads basis-universal images with extension "basis_linear", assuming linear
/// color space.
#[derive(Default)]
pub struct BasisLinearLoader {
    pub supported_compressed_formats: CompressedImageFormats,
}

impl AssetLoader for BasisLinearLoader {
    fn load<'a>(
        &'a self,
        bytes: &'a [u8],
        load_context: &'a mut LoadContext,
    ) -> BoxedFuture<'a, Result<(), Error>> {
        Box::pin(async move {
            load_context.set_default_asset(LoadedAsset::new(Image::from_buffer(
                bytes,
                ImageType::Extension("basis"),
                self.supported_compressed_formats,
                false,
            )?));
            Ok(())
        })
    }

    fn extensions(&self) -> &[&str] {
        &["basis_linear"]
    }
}
