use bevy::asset::io::Reader;
use bevy::asset::{AssetLoader, AsyncReadExt, LoadContext};
use bevy::render::texture::{CompressedImageFormats, Image, ImageSampler, ImageType, TextureError};
use bevy::utils::BoxedFuture;
use std::io;
use thiserror::Error;

// TODO: remove when https://github.com/bevyengine/bevy/issues/6371 is resolved
//
/// Loads basis-universal images with extension "basis_linear", assuming linear
/// color space.
#[derive(Default)]
pub struct BasisLinearLoader {
    pub supported_compressed_formats: CompressedImageFormats,
}

#[derive(Debug, Error)]
pub enum BasisLinearLoaderError {
    #[error(transparent)]
    Io(#[from] io::Error),
    #[error(transparent)]
    Texture(#[from] TextureError),
}

impl AssetLoader for BasisLinearLoader {
    type Asset = Image;
    type Error = BasisLinearLoaderError;
    type Settings = ();

    fn load<'a>(
        &'a self,
        reader: &'a mut Reader,
        _settings: &'a Self::Settings,
        _load_context: &'a mut LoadContext,
    ) -> BoxedFuture<'a, Result<Self::Asset, Self::Error>> {
        Box::pin(async move {
            let mut bytes = Vec::new();
            reader.read_to_end(&mut bytes).await?;
            Ok(Image::from_buffer(
                &bytes,
                ImageType::Extension("basis"),
                self.supported_compressed_formats,
                false,
                ImageSampler::Default,
            )?)
        })
    }

    fn extensions(&self) -> &[&str] {
        &["basis_linear"]
    }
}
